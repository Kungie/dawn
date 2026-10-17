# dmgbuild settings for Dawn's installer: drag Dawn.app onto Applications.
# Used by scripts/build-app.sh as: dmgbuild -s scripts/dmg-settings.py -D app=... -D bg=... Dawn build/Dawn.dmg
import os.path

app = defines["app"]
files = [app]
symlinks = {"Applications": "/Applications"}
format = "UDZO"
background = defines["bg"]          # dmgbuild picks up the @2x file next to it for Retina
window_rect = ((200, 140), (640, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 112
text_size = 13
icon_locations = {
    os.path.basename(app): (170, 200),
    "Applications": (470, 200),
}
