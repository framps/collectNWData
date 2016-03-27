#!/usr/bin/env python 
#-*- coding: utf-8 -*-
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
# Summary:
#   Script which invokes collectNWData.sh via a GUI 
#
# $Revision: 1.98 $
# $Date: 2014/05/07 20:55:33 $ 
#
# For details about collectNWData.sh:
#   See http://www.linux-tips-and-tricks.de/collecntnwdatae
#
# Latest version of collectNWDataGUI for download:
#   See http://www.linux-tips-and-tricks.de/CNDGUI_download
#
# Change history:
#   See http://www.linux-tips-and-tricks.de/CND_history
#
# See also:
#
# Latest version of collectNWData.sh for download:
#   See http://www.linux-tips-and-tricks.de/CND_download
#
# List of messages of collectNWData.sh with detailed help information:
#   See http://www.linux-tips-and-tricks.de/CND
#
# List of contributors for collectNWData.sh: 
#   See http://www.linux-tips-and-tricks.de/CND_contributors

try:
  import pygtk
  pygtk.require("2.0")
except:
  print "You need to install pyGTK or GTKv2 or set your PYTHONPATH correctly"
  print "try: export PYTHONPATH=/usr/local/lib/python2.2/site-packages/"
  sys.exit(1)
  
import gtk
import gtk.glade
import pango
import gobject

import threading
import gettext
import StringIO
import zipfile
import tempfile
import shutil
import signal
import shlex
import Queue
import re
import errno
import sys
import subprocess
import os
import locale
import datetime
import traceback
import getopt
import pexpect
import collectNWDataGUIResources
import urllib
from CommandExecutor import CommandExecutor       

### constants

CVS_DATE=' '.join("$Date: 2014/05/07 20:55:33 $".split(' ')[1:-1])+ " UTC"
CVS_REVISION=' '.join("$Revision: 1.98 $".split(' ')[1:-1])
VERSION="V0.1.3"

WINDOW_SIZE_INITIAL=(600,400)
WINDOW_SIZE_FINAL=(800,600)
SCRIPT_NAME="collectNWData"
SCRIPT_FILENAME=SCRIPT_NAME+".sh"
SCRIPT_RESULTFILE=SCRIPT_NAME+".txt"
GUI_NAME=os.path.splitext(os.path.basename(__file__))[0]   
GUI_FILENAME=GUI_NAME+".sh"
ERR_FILENAME=GUI_NAME+".err"
DESKTOP_FILENAME=GUI_NAME+".desktop"
LOGO_FILENAME=GUI_NAME+".jpg"
AUTHOR="framp at linux-tips-and-tricks dot de"
COPYRIGHT="Copyright (C) 2012 - 2016\n" + AUTHOR
WINDOW_TITLE="collectNWDataGUI"
INVOKED_AS_ROOT=os.geteuid() == 0
PEXPECT_LIC="pexpect.lic"
PEXPECT_COPYRIGHT="""
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

Bundled software\nPexpect\nCopyright (c) 2008 Noah Spurrier
http://pexpect.sourceforge.net/
See license details in pexpect.lic"""
CHECKSUM_WEBPAGE="http://www.linux-tips-and-tricks.de/index.php/View-document-details/81-collectNWDataGUI.html"

TEMPFILE_PREFIX="cnd-"

### Helper functions

def getCVSInfo():
#    guiInfo=[GUI_FILENAME,VERSION,CVS_REVISION,CVS_DATE]
    guiInfo=[GUI_FILENAME,VERSION]
    command="bash ./" + SCRIPT_FILENAME + " -v"
    process = subprocess.Popen(command.split(),stdout=subprocess.PIPE)
    result = process.communicate()[0]
    if process.returncode == 0:
        scriptVersion=result.split(' ')
        shellVersion=scriptVersion[1]
#        shellCVSRevision=scriptVersion[3][:-1]
#        shellCVSDate=' '.join(scriptVersion[5:])[:-2]
    else:
        shellVersion=''
#        shellCVSRevision=''
#        shellCVSDate=''
#    scriptInfo=[SCRIPT_FILENAME,shellVersion,shellCVSRevision,shellCVSDate]
    scriptInfo=[SCRIPT_FILENAME,shellVersion]
    return [guiInfo,scriptInfo]
            
def which(program):
    def is_exe(fpath):
        return os.path.isfile(fpath) and os.access(fpath, os.X_OK)

    fpath, fname = os.path.split(program)
    if fpath:
        if is_exe(program):
            return program
    else:
        for path in os.environ["PATH"].split(os.pathsep):
            exe_file = os.path.join(path, program)
            if is_exe(exe_file):
                return exe_file

    return None

def progressTimeout(progressbar):
    progressbar.pulse()
    return True 

class AsynchronousFileReader(threading.Thread):
    def __init__(self, fd, queue):
        threading.Thread.__init__(self)
        self._fd = fd
        self._queue = queue
 
    def run(self):
        for line in iter(self._fd.readline, ''):
            self._queue.put(line)
 
    def eof(self):
        return not self.is_alive() and self._queue.empty() 

### Main class
            
class CollectNWDataGUI:

    def getDesktopFilename(self):
    
        DESKTOP_EN='Desktop'
        DESKTOP_DE='Arbeitsfläche'
        
        desktopPath=''
        
        bashCommand = "xdg-user-dir DESKTOP"
        try:
            proc = subprocess.Popen(bashCommand.split(), stdout=subprocess.PIPE)
            desktopPath = proc.communicate()[0].strip('\n')
            rc = proc.returncode
            if rc != 0:
                print "Error with %s. rc %s" % (bashCommand,rc)
                desktopPath=''
        except Exception,e:
            print (_('Unable to derive desktop path'))
        #    print >> ERR_FILE, traceback.format_exc()
        #    print sys.exc_info()[0]

        if self.opts['ENV']:            
            self.writeLogFile("xdg-user-dir DESKTOP: %s" % (desktopPath))
    
        if not os.path.exists(desktopPath):        
            for path in [DESKTOP_EN,DESKTOP_DE]:
                if os.path.exists(path):
                    desktopPath=path
                    break
            return [False,DESKTOP_FILENAME] # fallback
                    
        return [True,desktopPath+'/'+DESKTOP_FILENAME]
    
    def writeLogFile(self,message):
        if self.opts['LOG']:
            if not hasattr(self,'ERR_FILE'):
                self.ERR_FILE=open(ERR_FILENAME,"w")
            print >> self.ERR_FILE, message
    
#    populate bundled glade xml, jpeg and I18N files 
    
    def importResources(self):
        
        # import I18N 
        
        I18NZipString=StringIO.StringIO(collectNWDataGUIResources.i18n_data)
        I18NZipFile=zipfile.ZipFile(I18NZipString, "r")
        I18NTempdir=tempfile.mkdtemp(prefix=TEMPFILE_PREFIX)
        I18NZipFile.extractall(I18NTempdir)    
        I18NTempdirName=I18NTempdir+"/locale"
        
        # following I18N initialization sequence with language fallback is adapted from http://wiki.maemo.org/How_to_Internationalize_python_apps
        
        # handle I18N detection and fallback
        
        DEFAULT_LANGUAGES = os.environ.get('LANG', '').split(':')
        DEFAULT_LANGUAGES += ['en_US']
     
        lc, encoding = locale.getdefaultlocale()
        if self.opts['ENV']:            
            self.writeLogFile("lc: %s - encoding: %s" % (lc,encoding))

        #'de_DE'      
        #'fr_FR'
            
        if self.opts['LOCALE']:
            lc=self.opts['LOCALE']

        if lc:
            languages = [lc]
                 
        languages += DEFAULT_LANGUAGES

        if self.opts['ENV']:            
            self.writeLogFile("Languages: %s" % (languages))            
     
        gettext.install (True,localedir=None, unicode=1)
     
        gettext.find(GUI_NAME, I18NTempdirName) 
        gettext.textdomain (GUI_NAME) 
        gettext.bind_textdomain_codeset(GUI_NAME, "UTF-8")
     
        language = gettext.translation (GUI_NAME, I18NTempdirName, languages = languages, fallback = True)
        language.install()

        self.localLanguage = str(lc).split('_')[0]
        if self.opts['ENV']:            
            self.writeLogFile("Local language: %s - %s" % (self.localLanguage, lc))     
        self.installedLanguage = str(language._info['language']).split('_')[0]
        if self.opts['ENV']:            
            self.writeLogFile("Installed language: %s - %s" % (self.installedLanguage, language._info['language']))
                
        shutil.rmtree(I18NTempdir) # delete directory
    
        # extract other resources
            
        self.GLADEXML=collectNWDataGUIResources.glade_data
        self.PEXPECTLIC=collectNWDataGUIResources.pexpect_lic
        
        loader = gtk.gdk.PixbufLoader('jpeg')
        loader.write(collectNWDataGUIResources.image_data)
        loader.close()
        self.LOGO = loader.get_pixbuf()

#    either install/run or uninstall

    def handleOpts(self):

        if self.opts['UNINSTALL']:
            self.uninstallFiles()
            return False                # no start GUI
        elif self.opts['CHECKSUM']:
            self.checkChecksum()
            return False
        else:
            self.installFilesIfNeeded()
            return True                 # start (default)

    def checkChecksum(self):
        
        filehandle = urllib.urlopen(CHECKSUM_WEBPAGE)
        rc=filehandle.getcode()

        if rc == 200:
            for line in filehandle.readlines():
                matchObj = re.match( r'<td>MD5 Checksum</td><td>(.*)</td>', line, re.I)
                if matchObj:
                    md5sumFromWebsite=matchObj.group(1)            
            filehandle.close()
            
            (rc,result)=self.executeCommand('md5sum ' + GUI_FILENAME)
            if rc != 0:
                mymd5sum=None
                print (_('Unable to calculate md5sum')) % (rc)
                return False
            else:
                mymd5sum=result.split()[0]
            
                if mymd5sum != md5sumFromWebsite:
                    print (_('different md5sum. Website: %s file: %s')) % (mymd5sum,md5sumFromWebsite)
                    return False
                else:
                    return True
        else:
            print (_('Unable to retrieve md5 checksum from %s. rc: %s')) % (GUI_FILENAME,rc)
            return False

#    make sure all files created are deleted again. Just keep the main script

    def uninstallFiles(self):

        uninstallingMessageWritten=False
        uninstallingMessage=(_('%s will be uninstalled')) % (GUI_NAME)

        desktopFound, desktopFile=self.getDesktopFilename()
        
        filesToRemove=[SCRIPT_FILENAME, SCRIPT_RESULTFILE, ERR_FILENAME, LOGO_FILENAME, desktopFile, PEXPECT_LIC]
    
        if not os.path.islink(SCRIPT_FILENAME):
            for f in filesToRemove:
                if os.path.exists(f):
                    if not uninstallingMessageWritten:
                        print uninstallingMessage
                        uninstallingMessageWritten=True
                    print (_('Deleting file %s')) % (f)    
                    os.remove(f)
                    
        if uninstallingMessageWritten:
            print (_('Uninstallation of %s finished')) % (GUI_NAME)
        else:
            print (_('%s not installed')) % (GUI_NAME)                       
            
#    Create files if they don't exist already
            
    def installFilesIfNeeded(self):
             
        installingMessageWritten=False
        installingMessage=(_('%s will be installed')) % (GUI_NAME)
               
        # TODO: Check if existing version is older/newer than bundled version 
        if not os.path.islink(SCRIPT_FILENAME):      # don't overwrite my link in my dev env
            if not os.path.exists(SCRIPT_FILENAME):
                if not installingMessageWritten:
                    print installingMessage
                    installingMessageWritten=True
                print (_('Creating file %s')) % (SCRIPT_FILENAME)
                f=open(SCRIPT_FILENAME,"w")
                f.write(collectNWDataGUIResources.script_data)
                f.close()
                os.chmod("./"+SCRIPT_FILENAME, 0755)     # make script executable 
                    
        if not os.path.exists(LOGO_FILENAME):
            if not installingMessageWritten:
                print installingMessage
                installingMessageWritten=True
            print (_('Creating file %s')) % (LOGO_FILENAME)
            f=open(LOGO_FILENAME,"wb")
            f.write(collectNWDataGUIResources.image_data)
            f.close()

        if not os.path.exists(PEXPECT_LIC):
            if not installingMessageWritten:
                print installingMessage
                installingMessageWritten=True
            print (_('Creating file %s')) % (PEXPECT_LIC)
            f=open(PEXPECT_LIC,"wb")
            f.write(collectNWDataGUIResources.pexpect_lic)
            f.close()
    
        homeDir=os.path.expanduser('~')        
    
        desktopFound, desktopFile=self.getDesktopFilename()
                
        if desktopFile:            
            if not os.path.exists(desktopFile):    
                if not installingMessageWritten:
                    print installingMessage
                    installingMessageWritten=True
        
        if not desktopFound:
            print (_('Unable to create desktop start icon'))

        print (_('Creating file %s')) % (desktopFile)
        result=''
        for line in collectNWDataGUIResources.desktop_data.split('\n'):
           line=line.replace('§',os.getcwd())
           result+=line+'\n'
        
        f=open(desktopFile,"w")
        f.write(result)
        f.close()
        os.chmod(desktopFile, 0755)    

        shellName=os.path.splitext(sys.argv[0])[0]+".sh"    # make me executable
        if os.path.exists(shellName):
            os.chmod(shellName, 0755)

        if installingMessageWritten:
            print (_('Installation of %s finished')) % (GUI_NAME)

#    Invocation option handling

    def parseOpts(self):
    
        self.opts=[]
    
        try:
            opts, args = getopt.getopt(sys.argv[1:], "cd:ehl:vu", 
                                       ["checksum",
                                        "debug",
                                        "environment",
                                        "help",
                                        "locale",
                                        "uninstall",
                                        "version"])
        except getopt.GetoptError, err:
            # print help information and exit:
            print str(err) # will print something like "option -a not recognized"
            self.usage()
            sys.exit(2)
        
        self.opts={'UNINSTALL': False, 'DEBUG': '', 'LOCALE': False, 'CHECKSUM': False, 'ENV': False, 'LOG': False}   
        for o, a in opts:
            if o in ("-u", "--uninstall"):
                self.opts['UNINSTALL'] = True
            elif o in ("-d", "--debug"):
                self.opts['DEBUG'] = a
            elif o in ("-l"):
                self.opts['LOCALE'] = a
            elif o in ("-e"):
                self.opts['ENV'] = True
                self.opts['LOG'] = True
            elif o in ("-c"):
                self.opts['CHECKSUM'] = True
            elif o in ("-v"):
                print COPYRIGHT
                (guiInfo,scriptInfo)=getCVSInfo()
                print (guiInfo[0]+" "+guiInfo[1]+" (Rev: "+guiInfo[2]+", Build: "+guiInfo[3]+")")
                print (scriptInfo[0]+" "+scriptInfo[1]+" (Rev: "+scriptInfo[2]+", Build: "+scriptInfo[3]+")")
                sys.exit(0)
            elif o in ("-h", "--help"):
                self.usage()
                sys.exit(0)
            else:
                print "Unknown option " + o + "skipped"
                        
    def usage(self):
        print GUI_FILENAME + " [-h|--help] [-u|--uninstall] [-d|--debug {gse}] [-l {locale}] [ -e | --environment]"

    def executeCommand(self,command):
        rc=None
        result=None
        try:
            proc = subprocess.Popen(command, stdout=subprocess.PIPE, shell=True)
            result = proc.communicate()[0]
            rc = proc.returncode
        except OSError, e:
            print "===> Error occurred in command %s" % (command)
            raise e         
            
        return (rc,result)   
    
#    Create script command line arguments
    
    def createCommandParms(self):
    
        if self.connectionType==0:  # wireless
            connection="-c 1"
            essid="-e %s" % (self.ssid)
        else:
            connection="-c 2"
            essid=""
            
        topology="-t %d" % (self.selectedTopology+1)        
        if self.selectedTopology in [2,3]:
            execution="-o %d" % self.selectedExecution
        else:
            execution=""
            
        if self.internationalPostingSelected:
            international="-i"
        else:
            international=""

        gui="-g"

        enabledParameters=[p for p in [connection,topology,gui,execution,essid,international] if p !=""]        
        parameters=' '.join(enabledParameters)
        
        if self.debugScriptEnabled:
            parameters+=" -d"
            
        self.debugMessage("collectNWData parms: %s" % parameters)
            
        return parameters            

#    Helper to write debugging messages

    def debugMessage(self,message):
#        print datetime.datetime.now().strftime("%H:%M:%S.%f")+" - " + message
        if self.debugGUIEnabled:
            textbuffer = self.debugView.get_buffer()
            textbuffer.insert(textbuffer.get_end_iter(), datetime.datetime.now().strftime("%H:%M:%S.%f")+" - " + message+'\n')
            self.debugView.scroll_to_mark(textbuffer.get_insert(), 0)
            while gtk.events_pending():
                gtk.mainiteration(gtk.FALSE)

    def setProcessingMessage(self,message):
        self.statusInfo.push(self.statusInfo.get_context_id("a"), message)
        self.debugMessage(message)

    def i18n(self):

        self.glade.get_object("rootButton").set_label(_('Invoke script as root'))        
        self.glade.get_object("rootButton").set_tooltip_text(_('RootToolTip'))

        rootDisabled=self.glade.get_object("rootmessagedialog")
        rootDisabled.set_markup(_('Are you sure you want to disable root invocation'))
        rootDisabled.format_secondary_text(_('This will reduce the analysis capabilities'))
    
        rootpasswordDialog=self.glade.get_object("rootPasswordDialog")
        rootpasswordDialog.set_markup(_('Enter root password'))
        rootpasswordDialog.format_secondary_text(_('Script should be executed as root'))

        invalidPWD=self.glade.get_object("rootpasswordmessagedialog")
        invalidPWD.set_markup(_('Invalid root password'))
        invalidPWD.format_secondary_text(_('Enter correct root password'))

        self.glade.get_object("internationalButton").set_label(_('Localized messages'))
        self.glade.get_object("internationalButton").set_tooltip_text(_('InternationalToolTip'))

        self.glade.get_object("wiredButton").set_label(_('Wired'))
        self.glade.get_object("wiredButton").set_tooltip_text(_('WiredToolTip'))
        self.glade.get_object("wirelessButton").set_label(_('Wireless'))
        self.glade.get_object("wirelessButton").set_tooltip_text(_('WirelessToolTip'))

        self.glade.get_object("okButton").set_label(_('OK'))
        self.glade.get_object("okButton").set_tooltip_text(_('OKToolTip'))

        self.glade.get_object("cancelButton").set_label(_('Cancel'))
        self.glade.get_object("cancelButton").set_tooltip_text(_('CancelToolTip'))

        self.glade.get_object("ssidEntry").set_tooltip_text(_('SSIDEntryField'))
        self.glade.get_object("ssidLabel").set_text(_('SSID'))
        self.glade.get_object("ssidLabel").set_tooltip_text(_('SSIDToolTip'))

        self.glade.get_object("ssidmessagedialog").set_markup(_('SSID missing'))
        self.glade.get_object("ssidmessagedialog").format_secondary_text(_('Please enter SSID of your accesspoint'))
        
        self.glade.get_object("topologyLabel").set_text(_('Topology'))
        self.glade.get_object("topologyLabel").set_tooltip_text(_('TopologyToolTip'))
        self.glade.get_object("topologyComboBox").set_tooltip_text(_('TopologyComboToolTip'))

        self.glade.get_object("executionLabel").set_text(_('Execution'))
        self.glade.get_object("executionLabel").set_tooltip_text(_('ExecutionToolTip'))
        self.glade.get_object("executionComboBox").set_tooltip_text(_('ExecutionComboToolTip'))        
        self.glade.get_object("connectionTypeLabel").set_text(_('Connection type'))        

        self.glade.get_object("donemessagedialog").set_markup(_('Network problem analysis complete'))
        self.glade.get_object("donemessagedialog").format_secondary_markup(_('Please execute following steps'))
    
        self.glade.get_object("filemenuitem").set_label(_('file'))        
        self.glade.get_object("debugMenuItemGUI").set_label(_('debugGUI'))        
        self.glade.get_object("debugMenuItemScript").set_label(_('debugScript'))
        self.glade.get_object("quitMenuItem").set_label(_('cancel'))

        self.glade.get_object("helpmenuitem").set_label(_('help'))
        self.glade.get_object("aboutmenuitem").set_label(_('about'))        

        self.glade.get_object("reportWindowLabel").set_text(_('Analysis summary'))
        self.glade.get_object("reportWindowLabel").set_tooltip_text(_('ReportToolTip'))

        self.glade.get_object("detailsWindowLabel").set_text(_('Analysis details'))
        self.glade.get_object("detailsWindowLabel").set_tooltip_text(_('DetailsToolTip'))

        self.glade.get_object("traceWindowLabel").set_text(_('Debug info'))

        self.glade.get_object("progressmessagedialog").set_markup(_('Please wait'))
        self.glade.get_object("progressmessagedialog").format_secondary_text(_('Collecting data and analyzing system'))

    def connectEvents(self):

        self.glade.get_object("rootButton").connect("clicked", self.rootButtonToggled)
        self.glade.get_object("internationalButton").connect("clicked", self.internationalButtonToggled)
        self.glade.get_object("wiredButton").connect("clicked", self.wiredButtonSelected)        
        self.glade.get_object("wirelessButton").connect("clicked", self.wirelessButtonSelected)        
        self.glade.get_object("okButton").connect("clicked", self.okButtonClicked)
        self.glade.get_object("cancelButton").connect("clicked", self.cancelButtonClicked)
        self.glade.get_object("ssidEntry").connect("changed", self.ssidEntered,self.glade.get_object("ssidEntry"))
                
        self.glade.get_object("aboutmenuitem").connect("activate",self.showAbout)
        
        self.glade.get_object("knownissuesmenuitem").connect("activate",self.showKnownIssues)
        self.glade.get_object("knownissuesmenuitem").set_sensitive(False)
        self.glade.get_object("knownissuesmenuitem").destroy()
        self.glade.get_object("quitMenuItem").connect("activate",self.cancelButtonClicked)
        self.glade.get_object("debugMenuItemGUI").connect("toggled",self.debugGUIMenuClicked)        
        
        self.glade.get_object("debugMenuItemScript").connect("toggled",self.debugScriptMenuClicked)        

        self.reportView=self.glade.get_object("reportView")
        self.reportView.modify_font(pango.FontDescription("courier 10"))
        
        self.detailsView=self.glade.get_object("detailsView")
        self.detailsView.modify_font(pango.FontDescription("courier 10"))

        self.debugView=self.glade.get_object("debugView")
        self.debugView.modify_font(pango.FontDescription("courier 10"))
     
        self.noteBook=self.glade.get_object("notebook1")
        self.reportPage=self.noteBook.get_nth_page(0)
        self.detailsPage=self.noteBook.get_nth_page(1)
        self.debugPage=self.noteBook.get_nth_page(2)
        
        self.progresswindow=self.glade.get_object("progressmessagedialog")        
        
        self.progressbar=self.glade.get_object("progressbar")
                
        self.topologyCombo=self.glade.get_object("topologyComboBox")
        self.topologyCombo.connect("changed", self.changedTopology)

        self.executionCombo=self.glade.get_object("executionComboBox")
        self.executionCombo.connect("changed", self.changedExecution)

        self.statusInfo = self.glade.get_object("statusbar")

#    ctor of class

    def __init__(self):

        self.parseOpts()
        self.importResources()

#        print _('Please ignore warnings')
                 
        if not self.handleOpts():       
            sys.exit(0)                      # nothing to do
        
        self.version=VERSION
        self.name=GUI_NAME
        self.process=None
        self.windowTitle=WINDOW_TITLE
        self.debugGUIEnabled='g' in self.opts['DEBUG']
        self.debugScriptEnabled='s' in self.opts['DEBUG']
#        self.debugOptionEnabled='e' in self.opts['DEBUG']
        self.debugOptionEnabled=True
        self.cancelButton=False
        self.cancelButtonInProgress=False
        self.internationalPostingSelected=True
        self.connectionType=0   # 0=WLAN, 1=WIRED
        self.topologyComboListItems=[[_('WLAN Accesspoint <-> Client'),_('WLAN Hardwarerouter <-> Client'),_('WLAN Accesspoint <-> LinuxRouter <-> Client'),_('WLAN Hardwarerouter <-> LinuxRouter <-> Client')],
                                     [_('DSL Modem <-> Client'),       _('DSL Hardwarerouter <-> Client'), _('DSL Modem <-> LinuxRouter <-> Client'),       _('DSL Hardwarerouter <-> LinuxRouter <-> Client')]]
        self.executionComboListItems=[_('Linux Client'),_('Linux Router')]
        self.selectedTopology=1                                        
        self.selectedExecution=1
        self.cancelClicked=False   
        self.ssid=""
        self.rootPassword=None
        self.rootSelected=True                       

        self.glade = gtk.Builder()
        self.glade.set_translation_domain('collectNWDataGUI')
        self.glade.add_from_string(self.GLADEXML)

#        if  self.opts['ROOT']:
#            self.glade.get_object("rootButton").set_sensitive(True)
#            self.glade.get_object("rootButton").set_active(True)
#        else:
#            self.rootSelected=False
#            self.glade.get_object("rootButton").set_sensitive(False)
#            self.glade.get_object("rootButton").set_active(False)

        self.i18n()

        # main window

        self.mainWindow=self.glade.get_object("mainWindow")
        self.mainWindow.set_property("icon",self.LOGO)

        self.mainWindow.set_title(self.windowTitle)
        self.mainWindow.set_default_size(WINDOW_SIZE_INITIAL[0],WINDOW_SIZE_INITIAL[1])
        self.mainWindow.connect("destroy",self.cancelButtonClicked)
        
        # event handling
        
        self.connectEvents()

        # init combos

        self.initializeExecution()                     
        self.initializeTopology()                     
               
        # prepare window
               
        self.mainWindow.show_all()
        self.detailsPage.hide()
            
        self.glade.get_object("executionHbox").set_sensitive(False)

        # handle debugging

        if self.debugGUIEnabled or self.debugOptionEnabled:
            self.glade.get_object("debugMenuItemGUI").set_active(self.debugGUIEnabled)
            self.debugGUIMenuClicked(self.glade.get_object("debugMenuItemGUI"))
        else:
            self.glade.get_object("debugMenuItemGUI").destroy()

        if self.debugScriptEnabled or self.debugOptionEnabled:
            self.glade.get_object("debugMenuItemScript").set_active(self.debugScriptEnabled)
            self.debugGUIMenuClicked(self.glade.get_object("debugMenuItemScript"))
        else:
            self.glade.get_object("debugMenuItemScript").destroy()
            
        if not self.debugGUIEnabled:
            self.debugPage.hide()

        entry=self.glade.get_object("ssidEntry")
        entry.grab_focus()
        entry.set_activates_default(True)                        

        # popup window for translation help

        if self.localLanguage != self.installedLanguage:
            langNotSupported=self.glade.get_object("languageNotSupported")
            self.debugMessage('Popup: Language not supported')
            langNotSupported.run()
            langNotSupported.hide()
                  
#    populate about window
                        
    def showAbout(self,widget):
        about=self.glade.get_object("aboutWindow")
        about.set_property("logo",self.LOGO)
        about.set_program_name(self.name)
        (guiInfo,scriptInfo)=getCVSInfo()
#        about.set_comments(guiInfo[0]+" "+guiInfo[1]+"\n(Rev: "+guiInfo[2]+", Build: "+guiInfo[3]+')\n\n'+scriptInfo[0]+" "+scriptInfo[1]+"\n(Rev: "+scriptInfo[2]+", Build: "+scriptInfo[3]+')')
        about.set_comments("\n\n"+guiInfo[0]+" "+guiInfo[1]+"\n\n"+scriptInfo[0]+" "+scriptInfo[1]+"\n")
        about.set_title(self.windowTitle)
        about.set_copyright(COPYRIGHT+'\n\n'+PEXPECT_COPYRIGHT)
                            
        self.debugMessage('Popup: About')
        about.run()
        about.hide()

#    Show known issues - not needed right now

    def showKnownIssues(self,widget):
        knownIssuesWindow=self.glade.get_object("knownIssuesWindow")
        knownIssues=self.glade.get_object("knownIssuesView")
        buffer=knownIssues.get_buffer()
        ki=['1) Cancel of running collectNWData.sh not possible',
            ]
        buffer.insert(buffer.get_end_iter(), '\n')
        for text in ki:
            buffer.insert(buffer.get_end_iter(), text+'\n')
        knownIssuesWindow.show()

#    populate the topology combo

    def initializeTopology(self):
        self.WirelessTopologyListstore = gtk.ListStore(str)
        for i in self.topologyComboListItems[0]:  
            self.WirelessTopologyListstore.append([i])

        self.WiredTopologyListstore = gtk.ListStore(str)
        for i in self.topologyComboListItems[1]:  
            self.WiredTopologyListstore.append([i])

        combobox=self.topologyCombo
        cell = gtk.CellRendererText()
        combobox.pack_start(cell)
        combobox.add_attribute(cell, 'text', 0)
        combobox.set_model(self.WirelessTopologyListstore)
        combobox.set_active(0)

#    populate the execution combo

    def initializeExecution(self):        
        self.ExecutionListstore = gtk.ListStore(str)
        for i in self.executionComboListItems:  
            self.ExecutionListstore.append([i])
              
        combobox=self.executionCombo
        cell = gtk.CellRendererText()
        combobox.pack_start(cell)
        combobox.add_attribute(cell, 'text', 0)
        combobox.set_model(self.ExecutionListstore)
        combobox.set_active(-1)

#    cancel running script

    def cancelProcess(self):
        if self.process != None:
            self.debugMessage("cancelProgress")
            self.process.close(force=True)
            self.setProcessingMessage(_('Processing canceled'))
        
    def on_MainWindow_delete_event(self, widget, event):
        self.cancelProcess()
        self.cleanUpFilesystem()
        gtk.main_quit()

#    misc event handling routines

    def debugGUIMenuClicked(self,menuItem):
        self.debugGUIEnabled=self.glade.get_object("debugMenuItemGUI").get_active()
        if self.debugGUIEnabled:
            self.debugPage.show()
        else:
            self.debugPage.hide()                                

    def debugScriptMenuClicked(self,menuItem):
        self.debugScriptEnabled=self.glade.get_object("debugMenuItemScript").get_active()            

    def changedTopology(self, combobox):
        index=combobox.get_active()
        if index:
            self.selectedTopology=index
        if index in [2,3]:
            self.glade.get_object("executionHbox").set_sensitive(True)
            self.executionCombo.set_active(0)
        else:
            self.glade.get_object("executionHbox").set_sensitive(False)
            self.executionCombo.get_model()
            self.executionCombo.set_active(-1)
            
    def changedExecution(self, executionbox):
        model=executionbox.get_model()
        index=executionbox.get_active()
        if index:
            self.selectedExecution=index

    def cancelButtonClicked(self,widget, data=None):
        self.debugMessage("cancelButtonClicked")
        self.cancelButton=True
        self.cancelProcess()
        gtk.main_quit()
        
    def cancelButtonClickedInProgress(self,widget, data=None):
        self.cancelButtonInProgress=True
        self.debugMessage("cancelButtonClickedInProgress")
        self.setProcessingMessage(_('Cancel requested during processing'))
        self.cancelProcess()        
                
    def wirelessButtonSelected(self,widget, data=None):
        self.debugMessage("Wireless - %s was toggled %s" % (data, ("OFF", "ON")[widget.get_active()]))
        if widget.get_active():
            self.glade.get_object("ssidHbox").set_sensitive(True)
            self.glade.get_object("ssidEntry").grab_focus()

        self.connectionWireless=widget.get_active()
        self.connectionType=0
        self.topologyCombo.set_model(self.WirelessTopologyListstore)
        self.topologyCombo.set_active(0)
                    
    def wiredButtonSelected(self,widget, data=None):        
        self.debugMessage("Wired - %s was toggled %s" % (data, ("OFF", "ON")[widget.get_active()]))
        if widget.get_active():
            self.glade.get_object("ssidHbox").set_sensitive(False)
        self.connectionWireless=not widget.get_active()
        self.connectionType=1
        self.topologyCombo.set_model(self.WiredTopologyListstore)
        self.topologyCombo.set_active(0)
            
    def rootButtonToggled(self,widget, data=None):        
        self.debugMessage("root - %s was toggled %s" % (data, ("OFF", "ON")[widget.get_active()]))
        self.rootSelected=widget.get_active()
        if not self.rootSelected:
            rootDisabled=self.glade.get_object("rootmessagedialog")
            rootDisabled.set_title(self.windowTitle)
            self.debugMessage('Popup: Question root to disable')
            response=rootDisabled.run()
            rootDisabled.hide()
            if response == gtk.RESPONSE_NO:     # doesn't want to turn off root invocation 
                self.rootSelected=True
                widget.set_active(True)                
            
    def internationalButtonToggled(self,widget, data=None):
        self.debugMessage("international - %s was toggled %s" % (data, ("OFF", "ON")[widget.get_active()]))
        self.internationalPostingSelected=widget.get_active()

    def cleanupOutputFiles(self):
        self.setProcessingMessage(_('Cleaning output files'))        
        command=CommandExecutor("./" + SCRIPT_FILENAME,"-g -a", self.rootPassword)
        (output,status)=command.execute()
        self.debugMessage("Cleanup RC: %s" % (status) )

    def ssidEntered(self, widget, entry):
        self.ssid = entry.get_text()

#    Get root password 

    def promptForRootPassword(self):
        
        rootpasswordDialog=self.glade.get_object("rootPasswordDialog")
        rootpasswordDialog.set_default_response(gtk.RESPONSE_OK)
        entry=self.glade.get_object("passwordEntry")
        entry.grab_focus()
        entry.set_activates_default(True)

        self.rootPassword=None

        self.setProcessingMessage(_('Prompting for root pwd'))
        while not self.rootPassword:        
            self.debugMessage('Popup: Prompt for root pwd')
            responseId=rootpasswordDialog.run()
        
            if responseId==gtk.RESPONSE_OK:
                self.rootPassword=self.glade.get_object("passwordEntry").get_text()            
                self.debugMessage('Root pwd entered')
            
            if self.rootPassword != '' or responseId != gtk.RESPONSE_OK:    # make sure we get a PWD     
                self.debugMessage('Empty root pwd entered')
                break        
        
        self.setProcessingMessage(_('Cleaning root PWD in prompt'))
        self.glade.get_object("passwordEntry").set_text("")
        rootpasswordDialog.hide()

        return responseId==gtk.RESPONSE_OK        

#    invoke script and handle error messages and invalid root pwd

    def handleScriptInvocation(self): 

        self.debugMessage('handleScriptInvocation - Entry')

        rootPasswordEntered=False
        if self.rootSelected:
            if not INVOKED_AS_ROOT:
                rootPasswordEntered=self.promptForRootPassword()
            else:
                rootPasswordEntered=True    # I'm already root
            if not rootPasswordEntered:
                self.startOver()
                self.debugMessage('handleScriptInvocation - Exit - False')
                return False
        try:        
            exitCode=self.executeShellScript(rootPasswordEntered)
            if (exitCode == 1 or exitCode == 125) and not self.cancelButtonInProgress:   # invalid PWD 1 for Mint, 125 for OpenSuSE
                # see http://www.gnu.org/software/coreutils/manual/html_node/su-invocation.html
                self.setProcessingMessage(_('Invalid password entered processing message'))
                invalidPWD=self.glade.get_object("rootpasswordmessagedialog")
                self.setProcessingMessage("Error messages: %s" % ('\n'.join(self.errLog)).strip('\n\r'))
                self.debugMessage('Popup: Invalid root pwd')
                invalidPWD.run()
                invalidPWD.hide()
                self.startOver()                        
                self.debugMessage('handleScriptInvocation - Exit - False')
                return False
            elif exitCode > 1:     # script error
                self.setProcessingMessage(_('Error running collectNWData.sh ExitCode %s') % (exitCode))
                error=self.glade.get_object("shellerrordialog")
                error.format_secondary_text("ExitCode %s" % (exitCode))
                self.debugMessage('Popup: Execution error %s' % (exitCode))
                error.run()
                error.hide()
                self.startOver()
                self.debugMessage('handleScriptInvocation - Exit - False')
                return False
            
        except Exception, err:
            self.debugMessage('Exception in execution %s' % (traceback.format_exc()))
#            print traceback.format_exc()
#            print sys.exc_info()[0]
            self.startOver()
            self.cleanupFileSystem()
            self.debugMessage('handleScriptInvocation - Exit - False')
            return False

        self.debugMessage('handleScriptInvocation - Exit - %s' % (not self.cancelButtonInProgress))
        
        return not self.cancelButtonInProgress        
        
#    display script results
                                       
    def handleScriptResults(self):
       
        self.debugMessage('handleScriptResults - Entry')
        self.setProcessingMessage(_('Reading analysis details'))        
   
        self.detailsPage.show()
        self.noteBook.set_current_page(1)
        
        if not os.path.exists('./'+SCRIPT_RESULTFILE):
            self.debugMessage('Unable to find script resultfile')
            self.debugMessage('handleScriptResults - Exit')        
            return
        
        inputFile=open('./'+SCRIPT_RESULTFILE,'r')
        textbuffer = self.detailsView.get_buffer()

        for line in inputFile:
            textbuffer.insert(textbuffer.get_end_iter(), line)
            self.detailsView.scroll_to_mark(textbuffer.get_insert(), 0)
#            time.sleep(.05)
            while gtk.events_pending():
                gtk.mainiteration(gtk.FALSE)
        inputFile.close()

#        Scroll top top of window

        scrollWindow=self.glade.get_object("detailsViewWindow")
        adjustment=scrollWindow.get_vadjustment()
        adjustment.set_value(0)
        reportWindow=self.glade.get_object("reportViewWindow")
        adjustment=reportWindow.get_vadjustment()
        adjustment.set_value(0)

#        switch back to analysis pane

        self.noteBook.set_current_page(0)

#       copy details into clipboard

        self.setProcessingMessage(_('Copying detailed analysis result into clipboard'))

        clipboard = gtk.clipboard_get()
        textbuffer=self.detailsView.get_buffer()
        startiter, enditer = textbuffer.get_bounds()
        textbuffer.select_range(startiter,enditer)
        textbuffer.copy_clipboard(clipboard)
        textbuffer.place_cursor(startiter)  # remove selection
        clipboard.store()

        window = gtk.Window()
        screen = window.get_screen()
        
        # resize window and place it in the middle of the screen
        
        self.mainWindow.set_gravity(gtk.gdk.GRAVITY_NORTH_WEST)
        self.mainWindow.move((gtk.gdk.screen_width() - WINDOW_SIZE_FINAL[0])/2, (gtk.gdk.screen_height() - WINDOW_SIZE_FINAL[1])/2)            
        self.mainWindow.resize(WINDOW_SIZE_FINAL[0],WINDOW_SIZE_FINAL[1])

        self.debugMessage("Window size %s:%s" % (WINDOW_SIZE_FINAL))
        self.debugMessage("Screen size %s:%s" % (gtk.gdk.screen_width(),gtk.gdk.screen_height()))

        self.setProcessingMessage(_('collectNWData.sh finished'))
        donemessage=self.glade.get_object("donemessagedialog")
        donemessage.set_title(self.windowTitle)
        self.debugMessage('Popup: Execution done')
        donemessage.run()
        donemessage.hide()
        
        self.debugMessage('handleScriptResults - Exit')
            
#    Wrapper for shell script invocation which pops up busy window and reads the resulting data 
                        
    def executeShellScript(self,rootPasswordEntered):

        self.debugMessage('executeShellScript - Entry')

        command=''
        exitCode=0            

        if rootPasswordEntered and not INVOKED_AS_ROOT:       # I'm not root already
            command='su -c '
            self.rootSelected=True
        else:
            self.rootSelected=False

        command=os.path.dirname(os.path.realpath(os.path.abspath(sys.argv[0])))+"/"+SCRIPT_FILENAME            
        parameters=self.createCommandParms()
#        scriptCall.extend(parameters.split(' '))
#        commandToExecute=command+'"'+ ' '.join(scriptCall)+'"'

        self.process=CommandExecutor(command, parameters=parameters, password=self.rootPassword,async=True,debug=self.debugScriptEnabled)

        self.debugMessage("Parameters: " + parameters)        
        self.setProcessingMessage(_('Running collectNWData.sh'))

        self.debugMessage("Command: " + str(command) + " " + str(parameters))        
        self.process.execute()
                               
        self.glade.get_object("okButton").set_sensitive(False)
        self.glade.get_object("cancelButton").set_sensitive(False)

        self.progresswindow.set_title(self.windowTitle)
        self.progresswindow.show()
        self.timer = gobject.timeout_add (10, progressTimeout, self.progressbar)
        
        cancelButton=self.progresswindow.action_area.get_children()[0]
        cancelButton.connect("clicked", self.cancelButtonClickedInProgress)

        textbuffer = self.reportView.get_buffer()

        self.setProcessingMessage(_('Reading screen output from collectNWData.sh'))
        
        self.errLog=[]

        while self.process.isalive():
            try:
                line=self.process.read_nonblocking(size=1000,timeout=0).strip('\r')
                self.errLog.append(line)
                if len(self.errLog) > 3:
                    self.errLog=self.errLog[1:]
                self.debugMessage("line - %s" % line)                
                textbuffer.insert(textbuffer.get_end_iter(), line)
                self.reportView.scroll_to_mark(textbuffer.get_insert(), 0)
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break
             
            while gtk.events_pending():
                gtk.mainiteration(gtk.FALSE)
                
        exitCode=self.process.getStatus()
        self.setProcessingMessage(_('Finished script execution'))
        self.debugMessage("collectNWData.sh RC: %s" % exitCode)
        if exitCode > 1 and exitCode != 125:
            self.errLog = self.process.before().strip('\r') + '\n --- ' + self.process.after().strip('\r')

        self.debugMessage("line f - now starts")                            
        try:
            lines=self.process.readlines()
            for line in lines:
                self.debugMessage("line f - %s" % line)                
                textbuffer.insert(textbuffer.get_end_iter(), line.strip('\r'))
                self.reportView.scroll_to_mark(textbuffer.get_insert(), 0)
        except ValueError,ex:      # process canceled or invalid pwd
            self.debugMessage("Value error %s" % (ex))
            pass

        self.glade.get_object("cancelButton").set_sensitive(True)
                
        self.progresswindow.hide()
        gobject.source_remove(self.timer) # stop timer

        self.debugMessage('executeShellScript - Exit: rc: %s' % (exitCode))

        return exitCode        
    
    def ssidRequiredAndInserted(self):
        
        if self.connectionType==0 and self.ssid=="":  # wireless and ssid missing
            ssidMissing=self.glade.get_object("ssidmessagedialog")
            self.debugMessage('Popup: SSID required')
            ssidMissing.run()
            ssidMissing.hide()
            return False
        else: 
            return True        

#    cleanup all temporary files created by script

    def cleanupFileSystem(self):        

        try:
            self.debugMessage("Cleaning up filesystem")
            (output,exitCode) = CommandExecutor("bash ./" + SCRIPT_FILENAME + " -g -k",password=self.rootPassword).execute()
            self.debugMessage("Cleaning up filesystem RC: %s" % (exitCode))
        except Exception,ex:
            self.debugMessage("Cleaning up filesystem: Exception occured %s" % (ex))
            pass

#    reset GUI into initial state so script can be called again

    def startOver(self):        
        
        self.debugMessage("Starting over")
        self.glade.get_object("okButton").set_sensitive(True)
        self.glade.get_object("cancelButton").set_sensitive(True)
        (self.cancelButton,self.cancelButtonInProgress) = (False,False)
        self.process=None
        self.setProcessingMessage('')

#    kick off script execution and result processing

    def okButtonClicked(self,widget, data=None):

        self.debugMessage("OK button clicked")        
        if not self.ssidRequiredAndInserted():
            return

#        self.cleanupOutputFiles()

#        switch back to analysis pane
    
        self.noteBook.set_current_page(0)
                
        # clean output area 

        self.debugMessage('Cleaning output area')        
        textbuffer = self.reportView.get_buffer()
        textbuffer.delete(textbuffer.get_start_iter(),textbuffer.get_end_iter())        
        textbuffer = self.detailsView.get_buffer()
        textbuffer.delete(textbuffer.get_start_iter(),textbuffer.get_end_iter())        
    
        if self.handleScriptInvocation():
            self.handleScriptResults()
        else:
            self.debugMessage('Cleaning output area')        
            textbuffer = self.reportView.get_buffer()
            textbuffer.delete(textbuffer.get_start_iter(),textbuffer.get_end_iter())        
            textbuffer = self.detailsView.get_buffer()
            textbuffer.delete(textbuffer.get_start_iter(),textbuffer.get_end_iter())
            self.debugMessage("Final processing. Cancel detected")
            
        self.cleanupFileSystem()
        self.startOver()        
    
def main():
                          
    try:      
        CollectNWDataGUI()
        gtk.main()
    except KeyboardInterrupt:
        pass
                
if __name__ == "__main__":
    main()
