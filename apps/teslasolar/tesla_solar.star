"""
Applet: Tesla Solar
Summary: Tesla Solar Panel Monitor
Description: Energy production and consumption monitor for your Tesla solar panels.
Author: jweier & marcusb
"""

load("cache.star", "cache")
load("encoding/base64.star", "base64")
load("encoding/json.star", "json")
load("http.star", "http")
load("humanize.star", "humanize")
load("render.star", "render")
load("schema.star", "schema")

TESLA_AUTH_URL = "https://auth.tesla.com/oauth2/v3/token"
URL = "https://owner-api.teslamotors.com/api/1/energy_sites/{}/live_status?language=en"

IMG = ""

CACHE_TTL = 25200

DUMMY_DATA = {
    "response": {
        "solar_power": 1920,
        "load_power": 799.800048828125,
        "grid_status": "Unknown",
        "grid_power": -1120.199951171875,
        "grid_services_power": 0,
        "generator_power": 0,
        "island_status": "island_status_unknown",
        "timestamp": "2023-03-17T14:46:12-04:00",
        "wall_connectors": [],
    },
}

SOLAR_PANEL = base64.decode("""
iVBORw0KGgoAAAANSUhEUgAAABUAAAAQCAYAAAD52jQlAAAArElEQVQ4ja2T2xGFIAxETxyrcOhM
y7M0xzb2fjA4kYcPrvsFCSzhBExCZDLDAHwuxZ5ovEq+MfIaWkYSqt3ikdLmlkG38dcmx1U9v2h8
721mVeaNRgkwpjCzbytTWABO43i4VDMe44lYqlaS4sb5ttKWiu5faQoL+7ae5pLKd+4ntQVPlCMo
mHpmOcNWLGc7+ES+uFevmELJNcU8ugG+rRKOx9/XoKph40P8rR8wcGBXI4UlEQAAAABJRU5ErkJg
gg==
""")
SOLAR_PANEL_OFF = base64.decode("""
iVBORw0KGgoAAAANSUhEUgAAABUAAAAQCAYAAAD52jQlAAAAd0lEQVQ4je2TwQrAIAxDo+y7e+iP
d5cJtY0iustgOWklsb4i8OsTKqxoZrZkLoX6r5FBRAAAqkrX7XIWXFmX3rijFDqTiEBVuz1D1bW+
yjKFBASJqX96ZDiqRbbVH5yyTKGrilxbzaOrwLtdAs+gdgdEAwcf4lg3XnREWPIOZLAAAAAASUVO
RK5CYII=
""")
GRID = base64.decode("""
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAt0lEQVQ4jYWQuxEDIQxEhcfFeIZm
HEEtTimHTmiBa4KYZC+xGKEToITR5+0KEYkAADIi54ycM6z+2wIkSEQUQnArg4cAQxJk+LouAgDn
nNPcULdcaq2Q/VrrPNN7BwDI1zIopTzvwMN6Ay2y2/A4oGsyf5lqiyil7N13OcPmHU4DMk/Rj/7v
+8E0wCJaoLWGFD1S9OB8wKcNJMiuE7z6swanlXcwg7puwlJAO8pDLWG5rlXfgv+4AXBeHhx5xCS7
AAAAAElFTkSuQmCC
""")
HOUSE = base64.decode("""
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAb0lEQVQ4jcWQQQrAMAgE19KX9dL/
v2h7arDRFT1VCIHEGVYBUbxu+ntUCybnkgBPJDu83jsSBbckGUyC7yklOnYUaEkSWwlcPwHQPGxm
ls2fJQj9anmVAADOTlOVLhXsQJXuUB/d+l/w2UE1q/p7AIUnlBV3qmXkAAAAAElFTkSuQmCC
""")
DOTS_LTR = base64.decode("""
R0lGODlhCgAFAIABAA31VAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJDwABACwAAAAACgAFAAAC
CYyPmWAc7pRMBQAh+QQJDwABACwAAAAACgAFAAACCIyPqWAcrmIsACH5BAkPAAEALAAAAAAKAAUA
AAIIjI+pAda8oioAOw==
""")
DOTS_RTL = base64.decode("""
R0lGODlhCgAFAIABAP/RGwAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQJDwABACwAAAAACgAFAAAC
CIyPqQHWvKIqACH5BAkPAAEALAAAAAAKAAUAAAIIjI+pYByuYiwAIfkECQ8AAQAsAAAAAAoABQAA
AgmMj5lgHO6UTAUAOw==
""")

def main(config):
    site_id = humanize.url_encode(config.str("site_id", ""))
    refresh_token = config.str("refresh_token")

    if refresh_token and site_id:
        url = URL.format(site_id)

        access_token_cached = cache.get("site_id")
        if access_token_cached != None:
            print("Hit! Using cached access token.")
            access_token = access_token_cached
        else:
            print("Miss! Getting new access token from Tesla API.")

            auth_rep = http.post(TESLA_AUTH_URL, json_body = {
                "grant_type": "refresh_token",
                "client_id": "ownerapi",
                "refresh_token": refresh_token,
                "scope": "openid email offline_access",
            })

            access_token = auth_rep.json()["access_token"]
            cache.set("site_id", access_token, ttl_seconds = CACHE_TTL)

        rep = http.get(url, headers = {"Authorization": "Bearer " + access_token})
        if rep.status_code != 200:
            fail("Tesla API request failed with status {}".format(rep.status_code))
        data = rep.body()
        o = json.decode(data)
        unit = "kW"
    else:
        print("Using Dummy Data")
        o = DUMMY_DATA
        unit = "DEMO"

    o = o["response"]

    points = []
    flows = []
    if o["solar_power"] > 0:
        IMG = SOLAR_PANEL
        dir = 1
    else:
        IMG = SOLAR_PANEL_OFF
        dir = 0
    points.append((IMG, o["solar_power"] / 1000))
    flows.append(dir)

    if o["load_power"] > 0:
        points.append((HOUSE, o["load_power"] / 1000))

    if o["grid_power"] < 0:
        points.append((GRID, -o["grid_power"] / 1000))
        dir = 1
    elif o["grid_power"] > 0:
        points.append((GRID, o["grid_power"] / 1000))
        dir = -1
    else:
        dir = 0

    flows.append(dir)

    columns = []
    for p in points:
        IMG, power = p
        columns.append(
            render.Column(
                main_align = "space_between",
                cross_align = "center",
                children = [
                    render.Image(src = IMG),
                    render.Text(
                        content = format_power(power),
                        height = 8,
                        font = "tb-8",
                        color = "#ffd11a",
                    ),
                    render.Text(
                        content = unit,
                        height = 8,
                        font = "tb-8",
                        color = "#ffd11a",
                    ),
                ],
            ),
        )
    dots = [render.Box(width = 18)]
    for dir in flows:
        if dir:
            el = render.Image(src = DOTS_LTR if dir == 1 else DOTS_RTL)
        else:
            el = render.Box(width = 10)
        dots.append(
            render.Stack(children = [render.Box(width = 21), el]),
        )
    return render.Root(
        child = render.Stack(
            children = [
                render.Row(
                    expanded = True,
                    main_align = "space_between",
                    children = columns,
                ),
                render.Column(
                    children = [
                        render.Box(height = 8),
                        render.Row(expanded = True, children = dots),
                    ],
                ),
            ],
        ),
    )

def format_power(p):
    if p:
        return humanize.float("#,###.##", p)
    else:
        return "0"

def get_schema():
    return schema.Schema(
        version = "1",
        fields = [
            schema.Text(
                id = "refresh_token",
                name = "Refresh Token",
                desc = "Refresh Token for the Tesla Owner API.",
                icon = "key",
            ),
            schema.Text(
                id = "site_id",
                name = "Site ID",
                desc = "The site ID that should be monitored.",
                icon = "solarPanel",
            ),
        ],
    )
