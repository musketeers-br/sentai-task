# Recursively replaces the value of any object key whose name ends in a
# credential-shaped suffix with the literal sentinel "<REDACTED>".
# Suffix match is case-insensitive and covers: password, token, secret,
# credential, sessionid, csrf. This single generic rule covers every
# concrete field name observed on the platform (access_token,
# refresh_token, sessionId, csrf, etc.) without needing a field-by-field
# allowlist.
def redact_leaf:
  if type == "object" then
    with_entries(
      if (.key | ascii_downcase | test("password$|token$|secret$|credential$|sessionid$|csrf$"))
      then .value = "<REDACTED>"
      else .value |= redact_leaf
      end
    )
  elif type == "array" then
    map(redact_leaf)
  else
    .
  end;
redact_leaf
