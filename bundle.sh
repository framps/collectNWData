#!/bin/bash
#
#    Copyright (C) 2006-2016 framp at linux-tips-and-tricks dot de
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
rm -f collectNWData.txt
rm -f collectNWDataGUI.pyc
rm -fr ~/collectNWDataTest/*
if [[ ! -d buildResults ]]; then
   mkdir buildResults
fi
zip buildResults/collectNWDataGUII18N.zip -r locale/* -x \*CVS\*
python ModulizeFiles.py
rm buildResults/collectNWDataGUII18N.zip 
zip buildResults/collectNWDataGUIBundle.zip coll*.py pexpect.py pexpect.lic CommandExecutor.py *.desktop
cat zipheader.sh buildResults/collectNWDataGUIBundle.zip > buildResults/collectNWDataGUI.sh
rm buildResults/collectNWDataGUIBundle.zip
rm -rf ~/collectNWDataTest
mkdir -p ~/collectNWDataTest
cp buildResults/collectNWDataGUI.sh ~/collectNWDataTest/collectNWDataGUI.sh
chmod +x ~/collectNWDataTest/collectNWDataGUI.sh
cd ~/collectNWDataTest
bash collectNWDataGUI.sh
