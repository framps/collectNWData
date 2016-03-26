#!/bin/bash
pygettext collectNWDataGUI.py
#msginit --locale=de_DE --output de_DE.po
#msginit --locale=en_US --output en_US.po
msgmerge -U de_DE.po messages.pot
msgmerge -U en_US.po messages.pot
#intltool-extract --type=gettext/glade collectNWDataGUI.glade
#xgettext -k_ -kN_ -o messages.pot collectNWDataGUI.glade.h
#msgmerge -U de_DE.po messages.pot
#msgmerge -U en_US.po messages.pot
msgfmt de_DE.po --output=locale/de/LC_MESSAGES/collectNWDataGUI.mo
msgfmt en_US.po --output=locale/en/LC_MESSAGES/collectNWDataGUI.mo

