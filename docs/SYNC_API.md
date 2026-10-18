# Offline sync API

The app is offline-first: every record a field officer captures is saved on the
device first and uploaded later by the sync engine. The backend endpoint is
`POST /api/v1/sync/` (Django, `insurance/views/sync.py`); photos go to
`POST /api/v1/upload/`.

Only users with role SUPERUSER, ADMIN, MANAGER, AGENT or ASSESSOR may sync
(others get HTTP 403).

## Identity: `client_uuid`

Every record created on the device gets a UUID v4 (`client_uuid`) at capture
time. The server upserts by it, so re-sending the same record after a dropped
connection updates it instead of creating a duplicate. Children reference
parents captured on the device with `<parent>_uuid`, or parents that came from
the server with the parent's server id (`<parent>`).

## Request

```json
{
  "last_sync": "2026-10-14T06:38:17.096317+00:00",
  "include_reference": true,
  "changes": {
    "farmers": [{
      "client_uuid": "…", "first_name": "Jane", "last_name": "Wanjiku",
      "id_number": "12345678", "phone_number": "0712345678", "email": null,
      "gender": "F", "date_of_birth": "1990-05-01", "farmer_category": null,
      "registration_latitude": "-1.286389", "registration_longitude": "36.817223",
      "next_of_kin":   [{"name": "", "relationship": "", "phone_number": ""}],
      "bank_accounts": [{"bank_name": "", "account_number": "", "account_name": ""}]
    }],
    "farms": [{
      "client_uuid": "…", "farmer_uuid": "…",
      "farm_name": "", "farm_size": "2.50", "unit_of_measure": "ACRES",
      "location_province": "", "location_district": "", "location_sector": "",
      "latitude": "-1.2", "longitude": "36.8", "status": "ACTIVE"
    }],
    "quotations": [{
      "client_uuid": "…", "farm_uuid": "…", "insurance_product": 3, "sum_insured": "50000"
    }],
    "claims": [{
      "client_uuid": "…", "quotation": 17,
      "estimated_loss_amount": "20000", "loss_details": {"cause": "Drought", "description": "…"}
    }],
    "inspections": [{
      "client_uuid": "…", "farm": 5, "inspection_type": "LOSS_ASSESSMENT",
      "status": "COMPLETED", "scheduled_date": "2026-10-14", "scheduled_time": "09:30",
      "completed_at": "2026-10-14T10:05:00+03:00",
      "check_in_latitude": "-1.2", "check_in_longitude": "36.8", "check_in_time": "…",
      "check_out_latitude": "…", "check_out_longitude": "…", "check_out_time": "…",
      "findings": {"damage_percent": 40}, "recommendations": ""
    }]
  }
}
```

- `last_sync`: the `server_time` from the previous successful sync, or `null`
  for a full download (first login / after reset).
- Send only records that are pending. Omit fields you don't have.
- Decimals may be sent as strings or numbers; dates as `YYYY-MM-DD`;
  datetimes as ISO-8601.

### Business rules enforced by the server

- Farmers are always created in the officer's organisation; `created_by` is
  the officer.
- **Quotations**: the server computes `premium_amount = sum_insured ×
  product.average_premium_rate / 100` and sets status `OPEN`. The device may show
  the same calculation as an estimate. The product must be ACTIVE.
  `farmer` is derived from the farm.
- **Claims** can only be filed on a policy whose status is `WRITTEN` or `PAID`,
  and `estimated_loss_amount` cannot exceed the policy's `sum_insured`. So the
  device should only offer written/paid policies (from downloaded quotations).
  `farmer` is derived from the policy; status is set to `OPEN`; the server
  generates `claim_number`.
- **Inspections**: `inspector` is the officer.
- Quotations not in `OPEN`/`DRAFT`, and claims not `OPEN`, are owned by the
  office: further device edits return `locked`.

## Response

```json
{
  "server_time": "2026-10-14T06:40:00+00:00",
  "results": {
    "farmers": [{"client_uuid": "…", "status": "created", "server_id": 41, "record": {…}}],
    "farms":   [{"client_uuid": "…", "status": "pending_parent", "server_id": null,
                 "errors": {"farmer": ["Linked record has not been synced yet."]}}]
  },
  "updates":   {"farmers": […], "farms": […], "quotations": […], "claims": […], "inspections": […]},
  "reference": {"crops": […], "crop_varieties": […], "seasons": […],
                "insurance_products": […], "cover_types": […], "product_categories": […]}
}
```

Per-item `status`:

| status | meaning | device action |
|---|---|---|
| `created` / `updated` | saved | store `server_id`, replace local copy with `record`, mark synced |
| `duplicate` | a farmer with this ID number already exists in the organisation (`server_id` is the existing farmer) | link the local farmer to `server_id`, mark synced, tell the officer |
| `locked` | the office has moved the record on | discard local edits, take the server copy from `updates` |
| `pending_parent` | the parent failed or isn't synced yet | keep pending; retry next sync |
| `error` | validation failed; `errors` is `{field: [messages]}` | mark as error and show the messages so the officer can fix and resubmit |

`updates` holds every record in the organisation changed since `last_sync`
(server serializer format; each includes `client_uuid` when it was captured on
a device, plus server ids like `farmer_id`, `farm_id`, `quotation_id`,
`claim_id`, `inspection_id`). Upsert locally by `client_uuid` when present,
otherwise by server id. Store `server_time` as the next `last_sync` only after
the whole response has been applied.

## Photos

`POST /api/v1/upload/` (multipart), after the owning record has synced:

| field | |
|---|---|
| `file` | JPEG/PNG, max 10MB |
| `entity_type` | `farmer` (profile photo) / `claim` / `inspection` |
| `entity_uuid` or `entity_id` | the owning record |
| `client_uuid` | the photo's own UUID; re-uploading it returns the existing photo (HTTP 200) |
| `caption`, `latitude`, `longitude` | optional |

Returns 201 (or 200 for a repeat) with `file_url`. 409 with
`code: pending_parent` means the owning record hasn't synced yet; retry after
the next sync.
