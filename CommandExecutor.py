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

import pexpect
import sys
import threading
import os

class CommandExecutor:

    def __init__(self,command,parameters="",password=None,async=False,debug=False):
        self._command=command
        self._parameters=parameters
        self._password=password
        self._asyncronous=async
        self._debug=debug
        self._commandToExecute='%s' % (self._command+" "+self._parameters)
        if password:
            self._commandToExecute='su -c "'+self._commandToExecute + '"'
            self._password=password
        if self._debug:
            print "Command: %s Args: %s PWD passed: %s" % (self._command,self._parameters,self._password != None)
            print self._commandToExecute

    def execute(self):
        if self._asyncronous:
            return self._executeAsync()
        else:
            return self._executeSync()

    def _executeSync(self):    
        if self._debug:
            print "ExecSync: %s PWD passed: %s" % (self._commandToExecute, self._password != None)
        if self._password:
            (self._output,self._status)=pexpect.run (self._commandToExecute, events={'.*:': self._password+'\n'}, withexitstatus=1)
        else:
            (self._output,self._status)=pexpect.run (self._commandToExecute, withexitstatus=1)
        
        return (self._output,self._status)

    def _executeAsync(self):        
        if self._debug:
            print "ExecAsync: %s PWD passed: %s" % (self._commandToExecute,self._password != None)
        if self._password:
            self._process = pexpect.spawn(self._commandToExecute)
            #self._process.logfile_read = sys.stdout
            if self._debug:
                self._process.logfile_read = open("collectNWDataGUI.trc","w")
            self._process.expect('.*:')
            self._process.sendline(self._password)
        else:
            self._process = pexpect.spawn(self._commandToExecute)
        
        return ('Started',0)

    def before(self):
        return self._process.before        

    def after(self):
        return self._process.after        

    def isalive(self):
        return self._process.isalive()
    
    def read_nonblocking(self,size=1,timeout=0):
        return self._process.read_nonblocking(size,timeout)

    def readline(self,size=-1):
        return self._process.readline(size)

    def readlines(self):
        return self._process.readlines()
    
    def getPid(self):
        return self._process.pid

    def getStatus(self):
        self._process.close()
        return self._process.exitstatus
    
    def close(self,force=False):
        if self._process.isalive():
            if  self._asyncronous and force:
                CommandExecutor('kill','%s' % (self._process.pid),password=self._password).execute()
            else:
                self._process.close(force)

def run(command):
    
    command.execute()
    
    while command.isalive():
        line=''
        try:
            line=command.read_nonblocking(size=100,timeout=0)
            sys.stdout.write(line.strip('\r'))
        except pexpect.TIMEOUT:
            pass
        except pexpect.EOF:
            break
        
    line=command.readlines()
    for l in line:
        print "f " + str(l).strip('\r'),

    print "status: %s" % (command.getStatus())        

if __name__ == "__main__":
    
    password=sys.argv[1]
    
#    run(CommandExecutor('lsx -la',async=True,password='xx',debug=True))
#    run(CommandExecutor('ls -la /',async=True,password=password,debug=True))
#    run(CommandExecutor(os.getcwd()+'/collectNWData.sh',async=True,parameters='-c 2 -t 2 -g -r -i',password=password))
#    run(CommandExecutor(os.getcwd()+'/collectNWData.sh',async=True,parameters='-c 2 -t 2 -g -r -i',password='xxx'))
    run(CommandExecutor('cat',parameters='/var/log/syslog',async=True,password=password))
        
