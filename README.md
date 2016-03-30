### Summary 

A lot of time network problems are posted in forums in order to find people to help to solve them. A lot of problems are configuration problems which can be fixed easily by the problem poster. This script collects a lot of network information and passes them to the NWEliza component, which analyzes them for common configuration errors. Errormessages point to webpages on this website which help to fix the problems.

If there is no way to get the problem fixed the collected information is very helpful to be posted in a forum. Thus people don't have to ask every time the same questions and ak for the same information. To speed up the problem solving process the resulting file of the script can be posted which might enable people to give an answer directly or to ask specific question to fix the problem.

collectNWData.sh is a shell script which helps everybody who has networkproblems on a Linux system to fix them. The system will be analyzed for common network configuration errors and error messages which help to solve the problem on your own will be created.If the network problem is an special problem the collected network information helps people in Linux forums to identify the network problems very fast and to help to solve them. 

collectNWDataGUI.sh is a GUI frontend for collectNWData.sh

### Documentation 
 
Documentation about collectNWData is available [here](http://www.linux-tips-and-tricks.de/en/details/)

### Downloads

Download of collectNWData.sh is possible [here](http://linux-tips-and-tricks.de/downloads/collectnwdata-sh/detail)
Download of GUI collectNWDataGUI.sh is possible [here](http://www.linux-tips-and-tricks.de/en/downloads/collectnwdatagui-sh/detail/)

### Bundle and test collectNWDataGUI.sh 

1. The script will bundle all resoures required in collectNWDataGUI.sh which will be created in directory buildResults
2. To test the build collectNWDataGUI.sh is called such that the whole code is extracted and the GUI will start

```
git clone https://github.com/framps/collectNWData.git
./bundle.sh
```
