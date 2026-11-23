"""Provision the CompassLink integration user on a DHIS2 instance.

    python3 provision-compasslink-user.py <secrets-file> <dhis2-url> user|sharing|token

  user     create user group + role (F_DATAVALUE_ADD) + user "compasslink" (Bo district),
           and add the user to the group (DHIS2 keeps membership on the group side)
  sharing  give the group data-write sharing on the data set, program and stage
  token    create a personal access token as the compasslink user

Reads DHIS2_ADMIN_PASSWORD from, and appends generated secrets to, the secrets file.
Never prints secrets. Clear DHIS2's cache (Data Administration → Maintenance) or
POST /api/maintenance/cacheClear after `sharing` if writes are still refused."""
import base64, json, secrets, string, sys, urllib.request, urllib.error

SECRETS = sys.argv[1]
U = sys.argv[2].rstrip("/") + "/api"
env = dict(l.strip().split("=", 1) for l in open(SECRETS) if "=" in l)

def call(method, path, body=None, user="admin", pw=None, ctype="application/json"):
    pw = pw or env["DHIS2_ADMIN_PASSWORD"]
    req = urllib.request.Request(U + path, method=method, data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Basic " + base64.b64encode(f"{user}:{pw}".encode()).decode(),
                 "Content-Type": ctype, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            t = r.read().decode(); return r.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:800]

def uid():
    a = string.ascii_letters; an = a + string.digits
    return secrets.choice(a) + "".join(secrets.choice(an) for _ in range(10))

step = sys.argv[3]
if step == "user":
    existing = call("GET", "/users?filter=username:eq:compasslink&fields=id")[1]["users"]
    if existing:
        print("user already exists:", existing[0]["id"]); sys.exit(0)
    pw = "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(24)) + "Aa1#"
    g, r, u = uid(), uid(), uid()
    bo = [{"id": "O6uvpzGd5pu"}]
    payload = {
        "userGroups": [{"id": g, "name": "CompassLink integration"}],
        "userRoles": [{"id": r, "name": "CompassLink integration",
                       "description": "Write aggregate data values and events from Compass via CompassLink",
                       "authorities": ["F_DATAVALUE_ADD"]}],
        "users": [{"id": u, "username": "compasslink", "password": pw, "firstName": "CompassLink", "surname": "Integration",
                   "userRoles": [{"id": r}], "userGroups": [{"id": g}],
                   "organisationUnits": bo, "dataViewOrganisationUnits": bo, "teiSearchOrganisationUnits": bo}],
    }
    s, res = call("POST", "/metadata?importStrategy=CREATE&atomicMode=ALL", payload)
    stats = res.get("stats") if isinstance(res, dict) else res
    print("metadata import:", s, res.get("status") if isinstance(res, dict) else "", stats)
    if s == 200 and res.get("status") == "OK":
        call("POST", f"/userGroups/{g}/users/{u}")
        with open(SECRETS, "a") as f:
            f.write(f"COMPASSLINK_DHIS2_PASSWORD={pw}\nCOMPASSLINK_USER_GROUP={g}\n")
        print("user group", g, "role", r, "user", u)

elif step == "sharing":
    g = env["COMPASSLINK_USER_GROUP"]
    for typ, oid in [("dataSets", "QX4ZTUbOt3a"), ("programs", "eBAyeGv0exc"), ("programStages", "Zj7UnCAulEk")]:
        patch = [{"op": "add", "path": f"/sharing/userGroups/{g}", "value": {"id": g, "access": "r-rw----"}}]
        s, res = call("PATCH", f"/{typ}/{oid}", patch, ctype="application/json-patch+json")
        s2, cur = call("GET", f"/{typ}/{oid}?fields=sharing[public,userGroups]")
        print(typ, oid, "patch", s, "->", cur["sharing"]["userGroups"].get(g))
    print("cache clear:", call("POST", "/maintenance/cacheClear")[0])

elif step == "token":
    pw = env["COMPASSLINK_DHIS2_PASSWORD"]
    s, me = call("GET", "/me?fields=username,organisationUnits[name]", user="compasslink", pw=pw)
    print("login as compasslink:", s, me if s != 200 else me["organisationUnits"])
    if "COMPASSLINK_DHIS2_PAT" in env:
        print("token already stored"); sys.exit(0)
    s, res = call("POST", "/apiToken", {"attributes": [], "expire": None}, user="compasslink", pw=pw)
    if s not in (200, 201):
        print("token create failed:", s, res); sys.exit(1)
    key = (res.get("response") or {}).get("key") or res.get("key")
    with open(SECRETS, "a") as f:
        f.write(f"COMPASSLINK_DHIS2_PAT={key}\n")
    print("token created, prefix", key[:4], "len", len(key))
