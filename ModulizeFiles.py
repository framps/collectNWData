#!/usr/bin/env python 
#-*- coding: utf-8 -*-

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

files = [("pexpect.lic", "pexpect_lic"),
         ("collectNWDataGUI.desktop", "desktop_data"),
         ("collectNWData.sh", "script_data"),
         ("collectNWDataGUI.glade", "glade_data"), 
         ("collectNWDataGUI.jpg", "image_data"), 
         ("buildResults/"+"collectNWDataGUII18N.zip", "i18n_data")]

fout=open("collectNWDataGUIResources.py", "wb")

for (file, name) in files:
    print "Modularizing %s as %s" % (file,name)

    with open(file, "rb") as fin:
        glade_data=fin.read()
        fout.write(name+"="+repr(glade_data)+'\n')
    
