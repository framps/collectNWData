#!/bin/bash
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
#   Script which analyzes network problems and collects network information on Linux systems
#   Useful for everybody who has networking issues on his distribution. The script
#   analyzes the system for most common networking config issues and writes meaningful
#   error messages which are explained in detail (see link below). That way it's possible
#   to fix most common config issues without any help. 
#
#   The script collects a lot of networking information from the system and creates an 
#   output file. This provides valuable information about the network and helps
#   people to help to fix the issue quickly if it's not a common networking config issue. 
#
# Change history:
#   See http://www.linux-tips-and-tricks.de/CND_history
#
# Latest version for download:
#   See http://www.linux-tips-and-tricks.de/CND_download
#
# List of messages with detailed help information:
#   See http://www.linux-tips-and-tricks.de/CND
#
# List of contributors: 
#   See http://www.linux-tips-and-tricks.de/CND_contributors
#
# Volunteers to translate messages in other languages: 
#   See http://www.linux-tips-and-tricks.de/CND_nls

#################################################################################
#################################################################################
#################################################################################
#
# --- various constants
#
#################################################################################
#################################################################################
#################################################################################

VERSION="V0.7.5.8"

MYSELF="${0##*/}"
CODE_BEGIN="[code]"
CODE_END="[/code]"
DEBUG="off"

GIT_DATE="$Date: 2016-05-22 17:35:50 +0200$"
GIT_DATE_ONLY=${GIT_DATE/: /}
GIT_DATE_ONLY=$(cut -f 2 -d ' ' <<< $GIT_DATE)
GIT_TIME_ONLY=$(cut -f 3 -d ' ' <<< $GIT_DATE) 
GIT_COMMIT="$Sha1: e8982e6$"
GIT_COMMIT_ONLY=$(cut -f 2 -d ' ' <<< $GIT_COMMIT | sed 's/\$//')

GIT_CODEVERSION="$MYSELF $VERSION $GIT_DATE_ONLY/$GIT_TIME_ONLY - $GIT_COMMIT_ONLY"

AUTHOR="framp at linux-tips-and-tricks dot de"
COPYRIGHT="Copyright (C) 2006-2016 ${AUTHOR}"
LICENSE="This program comes with ABSOLUTELY NO WARRANTY; This is free software, and you are welcome to redistribute it under certain conditions"

BASEURL="www.linux-tips-and-tricks.de"
CONTACT="framp@linux-tips-and-tricks.de"
HTTP_ROOT_ACCESS="http://$BASEURL/CND_ROOT"
HTTP_UPLOAD_URL="http://$BASEURL/CND_UPL"
HTTP_HELP_URL="http://$BASEURL/CND"
HTTP_XLATE_URL="http://$BASEURL/CND_NLS"
VAR_LOG_MESSAGE_FILE="/var/log/messages"

if [[ ! -e $VAR_LOG_MESSAGE_FILE ]]; then
	VAR_LOG_MESSAGE_FILE="/var/log/syslog"
fi

case $LANG in
	de_*)
		;;
    *)
        HTTP_HELP_URL="${HTTP_HELP_URL}#English"
        HTTP_ROOT_ACCESS="${HTTP_ROOT_ACCESS}#English"
        HTTP_UPLOAD_URL="${HTTP_UPLOAD_URL}#English"
        ;;
esac;

ESSID_MASK="§§§§§§§§";

SEPARATOR="=================================================================================================================="
CMD_PREFIX="====="
PROCESS_CHARS="|/-\\|/-"
process_chars_cnt=0
MINOR_SEPARATOR="------------------------------------------------------------------------------------------------------------------"
VERSION_STRING="$GIT_CODEVERSION"
NUMBER_OF_LINES_TO_CHECK_IN_VAR_LOG_MESSAGES=300
MAX_ERROR_PERCENT=5                   # acceptable error rate on interfaces (xmit and rcv)

# --- get the absolute path of script such that the output file can be written in the same directory

PRG_DIR=`dirname "$0"`
OLD_PWD=`pwd`
cd "$PRG_DIR"
export CND_DIR=`pwd`
cd "$OLD_PWD"

if [[ $UID -eq 0 || $USE_ROOT != "1" ]]; then
   CONSOLE_RESULT="${CND_DIR}/${MYSELF/.sh/}.con"
   ELIZA_RESULT="${CND_DIR}/${MYSELF/.sh/}.eza"
   COLLECT_RESULT="${CND_DIR}/${MYSELF/.sh/}.col"
   FINAL_RESULT="${CND_DIR}/${MYSELF/.sh/}.txt"
   FINAL_RESULT_SHORT_NAME="${MYSELF/.sh/}.txt"
   STATE="/tmp/${MYSELF}_S.$$"
   LOG=$COLLECT_RESULT
else
   chmod +x $CND_DIR/$MYSELF
fi

# check if predicatable interface names are used on system

function PNINused() {
	local rc
    debug ">>PNINused"

	if $IFCONFIG | $GREP "^(en|wl)"; then
		rc=0
	else
		rc=1
	fi	
  	PNIUSED=$rc
    debug "<<PNINused $rc"
    state "PNIN:$rc"
	return $rc
}


# check if openSuse config files are readable

function configReadable() { 

	local mask
	local rc
	rc=1
	mask="[arwe]"
    for f in `ls /etc/sysconfig/network/ifcfg-${mask}* 2>/dev/null`; do      # process all configs
		debug "$f"
		if [[ ! -r $f ]]; then	# file readable 
			rc=0
			break		
		fi
	done

	CONFIG_READABLE=$rc
	state "CFR:$rc"

	return $rc
}

function queryDistro () {

local distro
local detectedDistro="Unknown"
local regExpLsbFile="/etc/(.*)[-_]"
local skipFiles="lsb|os|upstream"

#################################################################################
# Query distro the script runs on
#################################################################################
#
# Returned distro       Distribution the script was tested on
# ---------------------------------------------------------
# suse                  openSuSE 11.0 (no lsb_release) and 11.2 (lsb_release)
# redhat                Fedora 12
# redhat                CentOS 5.4
# debian                Kubuntu 9.10
# debian                Debian 5.0.3
# arch                  Arch
# slackware             Slackware 13.0.0.0.0
# redhat                Mandriva 2009.1
# debian                Knoppix 6.2
# debian                Mint 8
#
#################################################################################

UNKNOWN_DISTRO=-1
SUSE=0
REDHAT=1
DEBIAN=2
ARCH=3
SLACKWARE=4

etcFiles=`ls /etc/*[-_]{release,version} 2>/dev/null`
for file in $etcFiles; do
   if [[ $file =~ $regExpLsbFile ]]; then
      nextDetectedDistro=${BASH_REMATCH[1]}
      if [[ $nextDetectedDistro =~ $skipFiles ]]; then
         continue
      fi
      detectedDistro=$nextDetectedDistro
      if [[ $nextDetectedDistro == "redhat"|| $nextDetectedDistro == "debian" ]]; then
         break
      fi
   else
      echo "??? Should not occur: Don't find any etcFiles ???"
      exit 255
   fi
done

DISTRO_NAME=$detectedDistro

distro=`echo $detectedDistro | tr "[:lower:]" "[:upper:]"`
DISTRO="DISTRO=\$$distro"
eval $DISTRO

}

#################################################################################
# --- tools needed by the script
#
# LSUSB checked at runtime - not beforehand - because it's not installed all the time
#################################################################################

MODS_OPT="HWINFO DHCPCD LSUSB RFKILL LSHW"	# optional commands
MODS_ALL="EGREP AWK SED IFCONFIG IWCONFIG IWLIST IPTABLES LSPCI GREP PERL ARP ROUTE LSMOD SORT PING TAIL"  # required commands

#################################################################################
# --- cleanup files in case of failure
#################################################################################

function cleanupTempFiles {
   rm -f "$LOG" 2>/dev/null
   rm -f "$ELIZA_RESULT" 2>/dev/null
   rm -f "$CONSOLE_RESULT" 2>/dev/null
   rm -f "$COLLECT_RESULT" 2>/dev/null
   rm -f $STATE 2>/dev/null
}

function cleanupFiles {
   rm -f "$FINAL_RESULT" 2>/dev/null
   cleanupTempFiles
   exit
}

trap 'cleanupFiles' SIGHUP SIGINT SIGPIPE SIGTERM

#################################################################################
#
# --- Messages in English and German
#
# (volunteers to translate the messages into other languages are welcome)
#
#################################################################################

# supported languages

MSG_EN=1      # english
MSG_DE=1      # german
MSG_PT=1      # portugiese
MSG_PL=1      # polish
MSG_CS=1      # czech
MSG_FR=1      # french

MSG_UNDEFINED=0
MSG_EN[$MSG_UNDEFINED]="Undefined message. Pls inform the author $CONTACT"
MSG_FR[$MSG_UNDEFINED]="Message inconnu. S'il vous plaît informer l'auteur $CONTACT"
MSG_CS[$MSG_UNDEFINED]="Nedefinována správa. Prosím, informujte autora $CONTACT"
MSG_DE[$MSG_UNDEFINED]="Unbekannte Meldung. Bitte den Author $CONTACT informieren"
MSG_PT[$MSG_UNDEFINED]="Por favor informe o autor $CONTACT"
MSG_PL[$MSG_UNDEFINED]="Niezdefiniowany komunikat. Proszę poinformuj autora $CONTACT"
MSG_INTERNAL_ERROR=1
MSG_EN[$MSG_INTERNAL_ERROR]="Internal error %1 occured. Pls inform the author $CONTACT"
MSG_FR[$MSG_INTERNAL_ERROR]="L'erreur interne %1 s'est produite . Svp informer l'auteur $CONTACT"
MSG_CS[$MSG_INTERNAL_ERROR]="Objevile se %1 chyba. Kontaktujte prosím autora $CONTACT"
MSG_DE[$MSG_INTERNAL_ERROR]="Interner Fehler %1 aufgetreten. Bitte den Author $CONTACT informieren"
MSG_PT[$MSG_INTERNAL_ERROR]="Erro interno %1. Por favor informe o autor $CONTACT"
MSG_PL[$MSG_INTERNAL_ERROR]="Wystąpił błąd wewnętrzny %1. Proszę poinformuj autora $CONTACT"
MSG_ELIZA_START_ANALYZE=2
MSG_EN[$MSG_ELIZA_START_ANALYZE]="--- NWEliza is analyzing the system for common network configuration errors ..."
MSG_FR[$MSG_ELIZA_START_ANALYZE]="--- NWEliza recherche dans le système les erreurs de configuration du réseau ..."
MSG_CS[$MSG_ELIZA_START_ANALYZE]="--- NWEliza analyzuje systém pro obecné chyby síťové konfigurace..."
MSG_DE[$MSG_ELIZA_START_ANALYZE]="--- NWEliza untersucht das System nach häufigen Netzwerkkonfigurationsfehlern ..."
MSG_PT[$MSG_ELIZA_START_ANALYZE]="--- NWEliza está procurando por erros comuns de configuração de rede no sistema ..."
MSG_PL[$MSG_ELIZA_START_ANALYZE]="--- NWEliza analizuje system pod kątem najczęstszych błędów konfiguracji sieci."
MSG_START_COLLECTING=3
MSG_EN[$MSG_START_COLLECTING]="--- NWCollect is collecting networkconfiguration information into file %1 ..."
MSG_FR[$MSG_START_COLLECTING]="--- NWCollect recueille l'information de configuration du réseau dans le fichier %1 ..."
MSG_CS[$MSG_START_COLLECTING]="--- NWCollect shromažďuje informaci o síťové konfiguraci  do souboru %1 ..."
MSG_DE[$MSG_START_COLLECTING]="--- NWCollect sammelt Netzwerkkonfigurationsinformationen in Datei %1 ..."
MSG_PT[$MSG_START_COLLECTING]="--- NWCollect está reunindo informações de configuração de rede no arquivo %1 ..."
MSG_PL[$MSG_START_COLLECTING]="--- NWCollect zbiera dane na temat konfiguracji sieci do pliku %1 ..."
MSG_CON_WRL=4
MSG_EN[$MSG_CON_WRL]="--- (1) Wireless connection (WLAN)"
MSG_FR[$MSG_CON_WRL]="--- (1) Connexion sans fil (WLAN)"
MSG_CS[$MSG_CON_WRL]="--- (1) Bezdrátové připojení (WLAN)"
MSG_DE[$MSG_CON_WRL]="--- (1) Kabellose Verbindung (WLAN)"
MSG_PT[$MSG_CON_WRL]="--- (1) Conexão sem fio (WLAN)"
MSG_PL[$MSG_CON_WRL]="--- (1) Połączenie bezprzewodowe (WLAN)"
MSG_ANSWER_CHARS_NO=5
MSG_EN[$MSG_ANSWER_CHARS_NO]="Nn"
MSG_FR[$MSG_ANSWER_CHARS_NO]="Nn"
MSG_CS[$MSG_ANSWER_CHARS_NO]="Nn"
MSG_DE[$MSG_ANSWER_CHARS_NO]="Nn"
MSG_PT[$MSG_ANSWER_CHARS_NO]="Nn"
MSG_PL[$MSG_ANSWER_CHARS_NO]="Nn"
MSG_ANSWER_CHARS_YES=6
MSG_EN[$MSG_ANSWER_CHARS_YES]="Yy"
MSG_FR[$MSG_ANSWER_CHARS_YES]="Oo"
MSG_CS[$MSG_ANSWER_CHARS_YES]="Aa"
MSG_DE[$MSG_ANSWER_CHARS_YES]="Jj"
MSG_PT[$MSG_ANSWER_CHARS_YES]="Ss"
MSG_PL[$MSG_ANSWER_CHARS_YES]="Tt"
MSG_MAIN_PROG_REQUIRED=7
MSG_EN[$MSG_MAIN_PROG_REQUIRED]="!!! Program %1 not found. Install program and invoke script again"
MSG_FR[$MSG_MAIN_PROG_REQUIRED]="!!! Le programme %1 est introuvable. Installez le programme et redémarrez le script"
MSG_CS[$MSG_MAIN_PROG_REQUIRED]="!!! Program %1 se nenašel. Nainstalujte program a spusťte skript znovu"
MSG_DE[$MSG_MAIN_PROG_REQUIRED]="!!! Das Programm %1 ist nicht verfügbar. Das Programm nachinstallieren und das Script danach noch einmal ausführen"
MSG_PT[$MSG_MAIN_PROG_REQUIRED]="!!! Programa %1 não encontrado. Instale o programa e execute esse script novamente"
MSG_PL[$MSG_MAIN_PROG_REQUIRED]="!!! Program %1 nie został znaleziony. Zainstaluj go i uruchom skrypt ponownie"
MSG_MAIN_NO_ERROR_DETECTED=8
MSG_EN[$MSG_MAIN_NO_ERROR_DETECTED]="--- No obvious errors/warnings detected. Post contents of file %1 in your favorite Linux forum and read $HTTP_UPLOAD_URL"
MSG_FR[$MSG_MAIN_NO_ERROR_DETECTED]="--- Aucune erreur ou avertissement évidents détectés. Postez le contenu du fichier %1 dans votre forum Linux préféré et lisez $HTTP_UPLOAD_URL"
MSG_CS[$MSG_MAIN_NO_ERROR_DETECTED]="--- Nejsou detekovány žádné zřejmé chyby/hlášení. Pošlete obsah souboru %1 do vašeho oblíbeného Linux fóra a přečtěte $HTTP_UPLOAD_URL"
MSG_DE[$MSG_MAIN_NO_ERROR_DETECTED]="--- Keine offensichtlichen Konfigurationsfehler/-warnungen gefunden. Die Datei %1 im bevorzugten Linux Forum posten und $HTTP_UPLOAD_URL lesen."
MSG_PT[$MSG_MAIN_NO_ERROR_DETECTED]="--- Nenhum erro/aviso óbvio detectado. Poste o conteúdo do arquivo %1 em seu fórum Linux preferido e leia $HTTP_UPLOAD_URL"
MSG_PL[$MSG_MAIN_NO_ERROR_DETECTED]="--- Nie znaleziono żadnego oczywistego błędu lub ostrzeżenia. Umieść zawartość pliku %1 na swoim ulubionym forum i przeczytaj $HTTP_UPLOAD_URL"
MSG_ASK_LANG=9
MSG_EN[$MSG_ASK_LANG]="--- Do you want to post the result file in an international forum (y/[n])?"
MSG_FR[$MSG_ASK_LANG]="--- Voulez-vous envoyer le fichier résultat à un forum international (o/[n])?"
MSG_CS[$MSG_ASK_LANG]="--- Chcete poslat soubour s výsledky do mezinárodního fóra (a/[n])?"
MSG_DE[$MSG_ASK_LANG]="--- Soll das Ergebnisfile in einem internationalen Forum gepostet werden (j/[n])?"
MSG_PT[$MSG_ASK_LANG]="--- Você quer postar o arquivo resultante em um fórum internacional (s/[n])?"
MSG_PL[$MSG_ASK_LANG]="--- Czy chcesz opublikować wyniki na międzynarodowym forum (t/[n])?"
MSG_SELECT_LANG=10
MSG_EN[$MSG_SELECT_LANG]="--- Please answer with yes (Y) or no (N):"
MSG_FR[$MSG_SELECT_LANG]="--- S'il vous plaît répondre par oui (O) ou non (N):"
MSG_CS[$MSG_SELECT_LANG]="--- Prosím, odpovězte takhle: ano (A) nebo ne (N):"
MSG_DE[$MSG_SELECT_LANG]="--- Bitte mit ja (J) oder nein (N) antworten:"
MSG_PT[$MSG_SELECT_LANG]="--- Por favor responda sim (S) ou não (N):"
MSG_PL[$MSG_SELECT_LANG]="--- Proszę odpowiedz tak (T) lub nie (N):"
MSG_GET_TOPOLOGY=11
MSG_EN[$MSG_GET_TOPOLOGY]="--- What's the type of networktopology?"
MSG_FR[$MSG_GET_TOPOLOGY]="--- Quel est le type de topologie du reséau?"
MSG_CS[$MSG_GET_TOPOLOGY]="--- Jaký je typ síťové topologie ?"
MSG_DE[$MSG_GET_TOPOLOGY]="--- Welche Netzwerktopologie liegt vor?"
MSG_PT[$MSG_GET_TOPOLOGY]="--- Qual é a topologia da rede?"
MSG_PL[$MSG_GET_TOPOLOGY]="--- Jaki jest typ topologi sieci?"
MSG_UNSUPPORTED_TOPOLOGY=12
MSG_EN[$MSG_UNSUPPORTED_TOPOLOGY]="--- Unknown topology"
MSG_FR[$MSG_UNSUPPORTED_TOPOLOGY]="--- Topologie inconnue"
MSG_CS[$MSG_UNSUPPORTED_TOPOLOGY]="--- Neznámá topologie"
MSG_DE[$MSG_UNSUPPORTED_TOPOLOGY]="--- Netzwerktopologie unbekannt"
MSG_PT[$MSG_UNSUPPORTED_TOPOLOGY]="--- Topologia desconhecida"
MSG_PL[$MSG_UNSUPPORTED_TOPOLOGY]="--- Nieznana topologia"
MSG_STRING=13
MSG_EN[$MSG_STRING]="%1."
MSG_PLEASE_CORRECT_ANSWER=14
MSG_EN[$MSG_PLEASE_CORRECT_ANSWER]="--- Please answer with 1-%1: "
MSG_FR[$MSG_PLEASE_CORRECT_ANSWER]="--- S'il vous plaît répondre avec 1-%1:"
MSG_CS[$MSG_PLEASE_CORRECT_ANSWER]="--- Prosím odpovězte s 1-%1: "
MSG_DE[$MSG_PLEASE_CORRECT_ANSWER]="--- Bitte mit 1-%1 anworten: "
MSG_PT[$MSG_PLEASE_CORRECT_ANSWER]="--- Por favor responda com 1-%1: "
MSG_PL[$MSG_PLEASE_CORRECT_ANSWER]="--- Proszę odpowiedz 1-%1: "
MSG_TOPO_DM_LC=15
MSG_EN[$MSG_TOPO_DM_LC]="--- (1) DSL modem <---> LinuxClient"
MSG_FR[$MSG_TOPO_DM_LC]="--- (1) Modem DSL <---> Client Linux"
MSG_CS[$MSG_TOPO_DM_LC]="--- (1) DSL modem <---> Linux klient"
MSG_DE[$MSG_TOPO_DM_LC]="--- (1) DSL modem <---> LinuxClient"
MSG_PT[$MSG_TOPO_DM_LC]="--- (1) Modem DSL <---> Cliente Linux"
MSG_PL[$MSG_TOPO_DM_LC]="--- (1) modem DSL <----> Klient Linux"
MSG_TOPO_DR_LC=16
MSG_EN[$MSG_TOPO_DR_LC]="--- (2) DSL HW router <---> LinuxClient"
MSG_FR[$MSG_TOPO_DR_LC]="--- (2) Routeur HW DSL <---> Client Linux"
MSG_CS[$MSG_TOPO_DR_LC]="--- (2) DSL HW router <---> Linux klient"
MSG_DE[$MSG_TOPO_DR_LC]="--- (2) DSL HW router <---> LinuxClient"
MSG_PT[$MSG_TOPO_DR_LC]="--- (2) Roteador DSL <---> Cliente Linux"
MSG_PL[$MSG_TOPO_DR_LC]="--- (2) DSL HW router <---> Klient Linux"
MSG_TOPO_DM_LR_LC=17
MSG_EN[$MSG_TOPO_DM_LR_LC]="--- (3) DSL modem  <---> LinuxRouter <---> LinuxClient"
MSG_FR[$MSG_TOPO_DM_LR_LC]="--- (3) Modem DSL <--->  Routeur Linux <---> Client Linux"
MSG_CS[$MSG_TOPO_DM_LR_LC]="--- (3) DSL modem  <---> Linux Router <---> Linux klient"
MSG_DE[$MSG_TOPO_DM_LR_LC]="--- (3) DSL modem  <---> LinuxRouter <---> LinuxClient"
MSG_PT[$MSG_TOPO_DM_LR_LC]="--- (3) Modem DSL <---> Roteador Linux <---> Cliente Linux"
MSG_PL[$MSG_TOPO_DM_LR_LC]="--- (3) DSL modem  <---> LinuxRouter <---> Klient Linux"
MSG_TOPO_DR_LR_LC=18
MSG_EN[$MSG_TOPO_DR_LR_LC]="--- (4) DSL HW router <---> LinuxRouter <---> LinuxClient"
MSG_FR[$MSG_TOPO_DR_LR_LC]="--- 4) Routeur HW DSL<---> Routeur Linux <---> Client Linux"
MSG_CS[$MSG_TOPO_DR_LR_LC]="--- (4) DSL HW router <---> LinuxRouter <---> LinuxClient"
MSG_DE[$MSG_TOPO_DR_LR_LC]="--- (4) DSL HW router <---> LinuxRouter <---> LinuxClient"
MSG_PT[$MSG_TOPO_DR_LR_LC]="--- (4) Roteador DSL <---> Roteador Linux <---> Cliente Linux"
MSG_PL[$MSG_TOPO_DR_LR_LC]="--- (4) DSL HW router <---> LinuxRouter <---> Klient Linux"
MSG_MAIN_POST_FILE=27
MSG_EN[$MSG_MAIN_POST_FILE]="--- If you are unsuccessful then place the contents of file %1 in the net\n--- (see $HTTP_UPLOAD_URL for links) \n--- and then paste the nopaste link on your favorite Linux forum. "
MSG_FR[$MSG_MAIN_POST_FILE]="--- Si vous ne réussissez pas,  placez le contenu du fichier %1 sur internet\n --- (voir $HTTP_UPLOAD_URL pour les liens) \n --- et puis collez le lien 'nopaste' sur votre forum Linux favori."
MSG_CS[$MSG_MAIN_POST_FILE]="--- Pokud posílání selhalo, umístněte obsah souboru %1 na internet\n--- (viz $HTTP_UPLOAD_URL pro odkazy) \n--- a pak vložte odkaz na vaše oblíbené Linux fórum. "
MSG_DE[$MSG_MAIN_POST_FILE]="--- Wenn eigene Lösungsversuche erfolglos waren dann den Inhalt der Datei %1 im Netz ablegen\n--- (Links siehe $HTTP_UPLOAD_URL) \n--- und dann der nopaste Link im bevorzugten Linux Forum posten."
MSG_PT[$MSG_MAIN_POST_FILE]="--- Se você não foi bem sucedido poste o conteúdo do arquivo %1 na internet\n--- (veja $HTTP_UPLOAD_URL para links) \n--- e informe o link nopaste em seu fórum Linux preferido."
MSG_PL[$MSG_MAIN_POST_FILE]="--- Jeżeli nie udało się proszę umieść zawartość pliku %1 w sieci\n--- (linki możesz znaleźć w $HTTP_UPLOAD_URL) \n--- i umieść link na swoim ulubionym forum. "
MSG_GET_HOST=29
MSG_EN[$MSG_GET_HOST]="--- On which host is the script executed?"
MSG_FR[$MSG_GET_HOST]="--- Sur quel ordinateur hôte le script est-il exécuté?"
MSG_CS[$MSG_GET_HOST]="--- Na kterém host-u je skript spuštěn?"
MSG_DE[$MSG_GET_HOST]="--- Auf welchem Rechner wird das Script ausgeführt?"
MSG_PT[$MSG_GET_HOST]="--- Em que host o script é executado?"
MSG_PL[$MSG_GET_HOST]="--- Na jakim komputerze został uruchomiony skrypt?"
MSG_UNSUPPORTED_HOST=30
MSG_EN[$MSG_UNSUPPORTED_HOST]="--- Invalid host"
MSG_FR[$MSG_UNSUPPORTED_HOST]="--- Hôte non valide"
MSG_CS[$MSG_UNSUPPORTED_HOST]="--- Nesprávný host"
MSG_DE[$MSG_UNSUPPORTED_HOST]="--- Ungültiger Rechner"
MSG_PT[$MSG_UNSUPPORTED_HOST]="--- Host inválido"
MSG_PL[$MSG_UNSUPPORTED_HOST]="--- Nieprawidłowy host"
MSG_HOST_RT=31
MSG_EN[$MSG_HOST_RT]="--- (2) LinuxRouter"
MSG_FR[$MSG_HOST_RT]="--- (2) Routeur Linux"
MSG_CS[$MSG_HOST_RT]="--- (2) Linux Router"
MSG_DE[$MSG_HOST_RT]="--- (2) LinuxRouter"
MSG_PT[$MSG_HOST_RT]="--- (2) Roteador Linux"
MSG_PL[$MSG_HOST_RT]="--- (2) LinuxRouter"
MSG_HOST_CL=32
MSG_EN[$MSG_HOST_CL]="--- (1) LinuxClient"
MSG_FR[$MSG_HOST_CL]="--- (1) Client Linux"
MSG_CS[$MSG_HOST_CL]="--- (1) Linux klient"
MSG_DE[$MSG_HOST_CL]="--- (1) LinuxClient"
MSG_PT[$MSG_HOST_CL]="--- (1) Cliente Linux"
MSG_PL[$MSG_HOST_CL]="--- (1) Klient Linux"
MSG_MAIN_BECOME_ROOT=33
MSG_EN[$MSG_MAIN_BECOME_ROOT]="--- Please enter the root password."
MSG_FR[$MSG_MAIN_BECOME_ROOT]="--- S'il vous plaît entrez le mot de passe root."
MSG_CS[$MSG_MAIN_BECOME_ROOT]="--- Prosím vložte root heslo."
MSG_DE[$MSG_MAIN_BECOME_ROOT]="--- Bitte das root Kennwort eingeben."
MSG_PT[$MSG_MAIN_BECOME_ROOT]="--- Por favor digite a senha de root."
MSG_PL[$MSG_MAIN_BECOME_ROOT]="--- Proszę wprowadzić hasło użytkownika root."
MSG_CON_WRD=40
MSG_EN[$MSG_CON_WRD]="--- (2) Wired connection"
MSG_FR[$MSG_CON_WRD]="--- (2) Connexion filaire"
MSG_CS[$MSG_CON_WRD]="--- (2) Drátové připojení"
MSG_DE[$MSG_CON_WRD]="--- (2) Kabelgebundene Verbindung"
MSG_PT[$MSG_CON_WRD]="--- (2) Conexão cabeada"
MSG_PL[$MSG_CON_WRD]="--- (2) Połączenie przewodowe"
MSG_GET_CONNECTION=41
MSG_EN[$MSG_GET_CONNECTION]="--- Which type of your network connection should be tested?"
MSG_FR[$MSG_GET_CONNECTION]="--- Quel type de connexion de votre réseau doit être testé?"
MSG_CS[$MSG_GET_CONNECTION]="--- Který typ vašeho síťového připojení se má testovat?"
MSG_DE[$MSG_GET_CONNECTION]="--- Welcher Netzwerkverbindungtyp soll getestet werden?"
MSG_PT[$MSG_GET_CONNECTION]="--- Que tipo de conexão da sua rede deve ser testado?"
MSG_PL[$MSG_GET_CONNECTION]="--- Który typ połączenia sieciowego ma zostać przetestowany?"
MSG_UNSUPPORTED_CONNECTION=42
MSG_EN[$MSG_UNSUPPORTED_CONNECTION]="--- Unknown network connection type"
MSG_FR[$MSG_UNSUPPORTED_CONNECTION]="--- Type de connexion réseau inconnu"
MSG_CS[$MSG_UNSUPPORTED_CONNECTION]="--- Neznámý typ připojení"
MSG_DE[$MSG_UNSUPPORTED_CONNECTION]="--- Netzwerkverbindungstyp unbekannt"
MSG_PT[$MSG_UNSUPPORTED_CONNECTION]="--- Tipo de conexão desconhecido"
MSG_PL[$MSG_UNSUPPORTED_CONNECTION]="--- Nieznany typ połączenia sieciowego"
MSG_EMPTY_LINE=43
MSG_EN[$MSG_EMPTY_LINE]=""
MSG_MAIN_GOTO_LINK=44
MSG_EN[$MSG_MAIN_GOTO_LINK]="--- Go to $HTTP_HELP_URL to get more detailed instructions \n--- about the error/warning messages and how to fix the problems on your own."
MSG_FR[$MSG_MAIN_GOTO_LINK]="--- Visitez $HTTP_HELP_URL pour obtenir des instructions plus détaillées \n --- sur les messages d'erreur/avertissement et comment résoudre vous même les problèmes."
MSG_CS[$MSG_MAIN_GOTO_LINK]="--- Jděte na $HTTP_HELP_URL pro získaní více detailních instrukcí \n--- o cybě/hlášení a jak problém manuálně opravit."
MSG_DE[$MSG_MAIN_GOTO_LINK]="--- Gehe zu $HTTP_HELP_URL um detailliertere Hinweise \n--- zu den Fehlermeldungen/Warnungen zu bekommen und wie die Fehler selbst beseitigt werden können."
MSG_PT[$MSG_MAIN_GOTO_LINK]="--- Acesse $HTTP_HELP_URL para obter instruções detalhadas \n--- sobre mensagens de erro/aviso e como resolver os problemas por conta própria."
MSG_PL[$MSG_MAIN_GOTO_LINK]="--- Przejdź do $HTTP_HELP_URL aby uzyskać szczegółowe instrukcje \n--- na temat błędów oraz ostrzeżeń oraz w jaki sposób samodzielnie usunąć problemy."
MSG_TOPO_AP_LC=46
MSG_EN[$MSG_TOPO_AP_LC]="--- (1) WLAN access point <---> LinuxClient"
MSG_FR[$MSG_TOPO_AP_LC]="--- (1) Point d'accès WLAN <---> Client Linux"
MSG_CS[$MSG_TOPO_AP_LC]="--- (1) WLAN access point <---> Linux klient"
MSG_DE[$MSG_TOPO_AP_LC]="--- (1) WLAN access point <---> LinuxClient"
MSG_PT[$MSG_TOPO_AP_LC]="--- (1) Ponto de acesso wireless <---> Cliente Linux"
MSG_PL[$MSG_TOPO_AP_LC]="--- (1) Punkt dostępowy WLAN <---> Klient Linux"
MSG_TOPO_WR_LC=47
MSG_EN[$MSG_TOPO_WR_LC]="--- (2) WLAN HW router <---> LinuxClient"
MSG_FR[$MSG_TOPO_WR_LC]="--- (2) Routeur HW WLAN <---> Client Linux"
MSG_CS[$MSG_TOPO_WR_LC]="--- (2) WLAN HW router <---> Linux klient"
MSG_DE[$MSG_TOPO_WR_LC]="--- (2) WLAN HW router <---> LinuxClient"
MSG_PT[$MSG_TOPO_WR_LC]="--- (2) Roteador wireless <---> Cliente Linux"
MSG_PL[$MSG_TOPO_WR_LC]="--- (2) WLAN HW router <---> Klient Linux"
MSG_TOPO_AP_LR_LC=48
MSG_EN[$MSG_TOPO_AP_LR_LC]="--- (3) WLAN access point <---> LinuxRouter <---> LinuxClient"
MSG_FR[$MSG_TOPO_AP_LR_LC]="--- (3) Réseau sans fil <---> Routeur Linux <---> Client Linux"
MSG_CS[$MSG_TOPO_AP_LR_LC]="--- (3) WLAN access point <---> Linux Router <---> Linux klient"
MSG_DE[$MSG_TOPO_AP_LR_LC]="--- (3) WLAN access point <---> LinuxRouter <---> LinuxClient"
MSG_PT[$MSG_TOPO_AP_LR_LC]="--- (3) Ponto de acesso wireless <---> Roteador Linux <---> Cliente Linux"
MSG_PL[$MSG_TOPO_AP_LR_LC]="--- (3) Punkt dostępowy WLAN <---> LinuxRouter <---> Klient Linux"
MSG_TOPO_WR_LR_LC=49
MSG_EN[$MSG_TOPO_WR_LR_LC]="--- (4) WLAN HW router <---> LinuxRouter <---> LinuxClient"
MSG_FR[$MSG_TOPO_WR_LR_LC]="--- (4) Routeur HW WLAN <---> Routeur Linux <---> Client Linux"
MSG_CS[$MSG_TOPO_WR_LR_LC]="--- (4) WLAN HW router <---> Linux Router <---> Linux klient"
MSG_DE[$MSG_TOPO_WR_LR_LC]="--- (4) WLAN HW router <---> LinuxRouter <---> LinuxClient"
MSG_PT[$MSG_TOPO_WR_LR_LC]="--- (4) Roteador wireless <---> Roteador Linux <---> Cliente Linux"
MSG_PL[$MSG_TOPO_WR_LR_LC]="--- (4) WLAN HW router <---> LinuxRouter <---> Klient Linux"
MSG_ASK_FOR_ROOT=59
MSG_EN[$MSG_ASK_FOR_ROOT]="--- Invoking this script as root allows a more detailed analysis and will give better results. \n--- If you have any concerns to execute the script as root please read $HTTP_ROOT_ACCESS.\n--- Do you want to run the script as root ([y]/n)?"
MSG_FR[$MSG_ASK_FOR_ROOT]="--- Invoquer ce script en tant que root permet une analyse plus détaillée et donnera de meilleurs résultats. \n --- Si vous avez des inquiétudes sur l' exécution du script en tant que root, s'il vous plaît lisez $HTTP_ROOT_ACCESS. \n --- Voulez-vous exécuter le script en tant que root ([o] / n)"
MSG_CS[$MSG_ASK_FOR_ROOT]="--- Spyštění skriptu jako root umožňuje detailnější analýzu a lepší výsledky. \n--- Pokud máte jakékoli zaujetí spustit skript jako root, prosím přečtěte si $HTTP_ROOT_ACCESS.\n--- Chcete spustit skript jako root ([a]/n)?"
MSG_DE[$MSG_ASK_FOR_ROOT]="--- Der Aufruf des Scripts als root erlaubt eine detailiertere Analyse und liefert bessere Ergebnisse. \n--- Falls Bedenken existieren das Script als root auszuführen bitte $HTTP_ROOT_ACCESS lesen.\n--- Willst Du das Script als root ausführen lassen ([j]/n)?"
MSG_PT[$MSG_ASK_FOR_ROOT]="--- Executar esse script como root permite uma análise mais detalhada e melhores resultados. \n--- Se você se preocupa em executar o script como root por favor leia $HTTP_ROOT_ACCESS.\n--- Você quer executar o script como root ([s]/n)?"
MSG_PL[$MSG_ASK_FOR_ROOT]="--- Uruchomienie tego skryptu jako root pozwala na uzyskanie bardziej szczegółowej analizy i przeważnie daje lepsze rezultaty.\n--- Jeżeli masz jakiekolwiek obawy z uruchamianiem skryptu jako root proszę przeczytaj $HTTP_ROOT_ACCESS.\n --- Czy mam uruchomić skrypt jak użytkownik root ([t]/n)?"
MSG_GET_ESSID=60
MSG_EN[$MSG_GET_ESSID]="--- Please enter the WLAN SSID you want to connect to (Will be masqueraded in output file): "
MSG_FR[$MSG_GET_ESSID]="--- S'il vous plaît, indiquez le SSID du WLAN auquel vous voulez vous connecter (il sera masqué dans le fichier de sortie):"
MSG_CS[$MSG_GET_ESSID]="--- Prosím vložte WLAN SSID ke kterému se chcete připojit (bude změněno ve výsledném souboru): "
MSG_DE[$MSG_GET_ESSID]="--- Bitte die WLAN SSID zu der verbunden werden soll eingeben (Wird in der Ausgabedatei maskiert): "
MSG_PT[$MSG_GET_ESSID]="--- Por favor digite a SSID da rede sem fio à qual quer se conectar (será mascarada no arquivo de saída): "
MSG_PL[$MSG_GET_ESSID]="--- Proszę wprowadź nazwę sieci bezprzewodowej (WLAN SSID) do której chcesz się połączyć (nazwa będzie niewidoczna w pliku wynikowym): "
MSG_GOT_ESSID=61
#         Attention: Message text below used in regex to masquerade SSID !
MSG_EN[$MSG_GOT_ESSID]="--- WLAN SSID to connect to: %1"
MSG_FR[$MSG_GOT_ESSID]="--- WLAN SSID à connecter: %1"
MSG_CS[$MSG_GOT_ESSID]="--- WLAN SSID připojit: %1"
MSG_DE[$MSG_GOT_ESSID]="--- WLAN SSID zu der verbunden werden soll: %1"
MSG_PT[$MSG_GOT_ESSID]="--- WLAN SSID da rede local sem fio a conectar: %1"
MSG_PL[$MSG_GOT_ESSID]="--- WLAN SSID do połączenia: %1"

MSG_ASK_FOR_XLATION=62
MSG_EN[$MSG_ASK_FOR_XLATION]="==> Messages for your language are not translated right now and thus you get all messages in English.\n==> Any help to translate messages into your language is welcome.\n==> There is no programming expertise required. Native speakers will need about 1 hour to translate the messages.\n==> Pls goto $HTTP_XLATE_URL to get more details how to help to translate script messages into your language."
#
#
#
MSG_NO_NIC_FOUND=300
MSG_EN[$MSG_NO_NIC_FOUND]="!!! CND0100E: No network card for the selected connection type was found on the system"
MSG_FR[$MSG_NO_NIC_FOUND]="!!! CND0100E: Aucune carte réseau pour le type de connexion sélectionné a été trouvée sur le système"
MSG_CS[$MSG_NO_NIC_FOUND]="!!! CND0100E: Nenašla se žádná síťová karta  pro zvolený typ připojení"
MSG_DE[$MSG_NO_NIC_FOUND]="!!! CND0100E: Keine Netzwerkkarte für den gewählten Verbindungstyp kann auf dem System gefunden werden"
MSG_PT[$MSG_NO_NIC_FOUND]="!!! CND0100E: Nenhuma placa de rede para a conexão escolhida foi encontrada no sistema"
MSG_PL[$MSG_NO_NIC_FOUND]="!!! CND0100E: Nie znaleziono kart sieciowych umożliwiających połączenie wybranego typu"
MSG_NO_VALID_NI_FOUND=301
MSG_EN[$MSG_NO_VALID_NI_FOUND]="!!! CND0110E: For the selected connection type there was no active network interface found on your system"
MSG_FR[$MSG_NO_VALID_NI_FOUND]="!!! CND0110E: Aucune interface réseau active n'a été trouvée sur votre système pour le type de connexion sélectionnée."
MSG_CS[$MSG_NO_VALID_NI_FOUND]="!!! CND0110E: Nenašlo se žádné aktivní síťové rozhraní pro zvolený typ připojení"
MSG_DE[$MSG_NO_VALID_NI_FOUND]="!!! CND0110E: Es wurde keine aktives Netzwerkinterface auf dem System für der gewählten Verbindungstyp gefunden"
MSG_PT[$MSG_NO_VALID_NI_FOUND]="!!! CND0110E: Nenhuma interface de rede ativa foi encontrada no sistema para a conexão escolhida"
MSG_PL[$MSG_NO_VALID_NI_FOUND]="!!! CND0110E: Nie aktywnych urządzeń dla wybranego typu połączenia"
MSG_NO_IP_ASSIGNED_TO_NIC=302
MSG_EN[$MSG_NO_IP_ASSIGNED_TO_NIC]="!!! CND0120E: Network card %1 has no IP address"
MSG_FR[$MSG_NO_IP_ASSIGNED_TO_NIC]="!!! CND0120E: La carte réseau %1 n'a pas d'adresse IP"
MSG_CS[$MSG_NO_IP_ASSIGNED_TO_NIC]="!!! CND0120E: Síťová karta %1 nemá žádnou IP adresu"
MSG_DE[$MSG_NO_IP_ASSIGNED_TO_NIC]="!!! CND0120E: Die Netzwerkkarte %1 hat keine IP Adresse"
MSG_PT[$MSG_NO_IP_ASSIGNED_TO_NIC]="!!! CND0120E: A placa de rede %1 não está associada a um endereço IP"
MSG_PL[$MSG_NO_IP_ASSIGNED_TO_NIC]="!!! CND0120E: Karta sieciowa %1 nie ma przydzielonego adresu IP"
MSG_DUPLICATE_NETWORKS=303
MSG_EN[$MSG_DUPLICATE_NETWORKS]="!!! CND0130E: There is more than one network card defined in the same subnet: %1"
MSG_FR[$MSG_DUPLICATE_NETWORKS]="!!! CND0130E: Il y a plus d'une carte réseau définies dans le même sous-réseau: %1"
MSG_CS[$MSG_DUPLICATE_NETWORKS]="!!! CND0130E: Je definováno více síťových karet  ve stejném subnet-u/podsíti: %1"
MSG_DE[$MSG_DUPLICATE_NETWORKS]="!!! CND0130E: Es ist mehr als eine Netzwerkkarte im selben Subnetz definiert: %1"
MSG_PT[$MSG_DUPLICATE_NETWORKS]="!!! CND0130E: Há mais de uma placa de rede associada à mesma subrede: %1"
MSG_PL[$MSG_DUPLICATE_NETWORKS]="!!! CND0130E: Więcej niż jedna karta sieciowa jest przydzielona do tej samej podsieci: %1"
MSG_NO_DEFAULT_GATEWAY_SET=304
MSG_EN[$MSG_NO_DEFAULT_GATEWAY_SET]="!!! CND0140E: No default gateway set on your system"
MSG_FR[$MSG_NO_DEFAULT_GATEWAY_SET]="!!! CND0140E: Aucune passerelle n'est définie sur votre système"
MSG_CS[$MSG_NO_DEFAULT_GATEWAY_SET]="!!! CND0140E: V systému není nastavena žádná brana/gateway"
MSG_DE[$MSG_NO_DEFAULT_GATEWAY_SET]="!!! CND0140E: Kein default gateway auf dem System definiert"
MSG_PT[$MSG_NO_DEFAULT_GATEWAY_SET]="!!! CND0140E: Gateway padrão não especificado nesse sistema"
MSG_PL[$MSG_NO_DEFAULT_GATEWAY_SET]="!!! CND0140E: Brak domyślnej bramy"
MSG_CHECK_DEFAULT_GATEWAY_SETTING=305
MSG_EN[$MSG_CHECK_DEFAULT_GATEWAY_SETTING]="!!! CND0150E: There might be a problem with the default gateway definition %1 on interface %2"
MSG_FR[$MSG_CHECK_DEFAULT_GATEWAY_SETTING]="!!! CND0150E: Il pourrait y avoir un problème avec la définition de la passerelle par défaut %1 sur l'interface %2"
MSG_CS[$MSG_CHECK_DEFAULT_GATEWAY_SETTING]="!!! CND0150E: Může být problém s přednastavenou bránou %1 v síťovém rozhraní %2"
MSG_DE[$MSG_CHECK_DEFAULT_GATEWAY_SETTING]="!!! CND0150E: Es kann ein Problem mit der default gateway definition %1 am Interface %2 vorliegen"
MSG_PT[$MSG_CHECK_DEFAULT_GATEWAY_SETTING]="!!! CND0150E: Pode haver um problema com a especificação do gateway padrão %1 na interface %2"
MSG_PL[$MSG_CHECK_DEFAULT_GATEWAY_SETTING]="!!! CND0150E: Ustawienie domyślnej bramy %1 na urządzeniu %2 może stwarzać problemy"
MSG_NAMESERVER_NOT_ACCESSIBLE=306
MSG_EN[$MSG_NAMESERVER_NOT_ACCESSIBLE]="!!! CND0160E: Unable to access nameserver with IP %1 defined in /etc/resolv.conf"
MSG_FR[$MSG_NAMESERVER_NOT_ACCESSIBLE]="!!! CND0160E: Impossible d'accéder au serveur de noms d' IP %1 défini dans /etc/resolv.conf"
MSG_CS[$MSG_NAMESERVER_NOT_ACCESSIBLE]="!!! CND0160E: Nemohu se připojit nameserver s IP %1 nastavenou v /etc/resolv.conf"
MSG_DE[$MSG_NAMESERVER_NOT_ACCESSIBLE]="!!! CND0160E: Auf den definierter Nameserver mit der IP %1 in /etc/resolv.conf kann nicht zugegriffen werden"
MSG_PT[$MSG_NAMESERVER_NOT_ACCESSIBLE]="!!! CND0160E: Não foi possível acessar o servidor de nomes %1 especificado em /etc/resolv.conf"
MSG_PL[$MSG_NAMESERVER_NOT_ACCESSIBLE]="!!! CND0160E: Serwer nazw %1 zdefiniowany w pliku /etc/resolv.conf jest nieosiągalny"
MSG_NO_NAMESERVER_DEFINED=307
MSG_EN[$MSG_NO_NAMESERVER_DEFINED]="!!! CND0170E: No nameserver defined in /etc/resolv.conf"
MSG_FR[$MSG_NO_NAMESERVER_DEFINED]="!!! CND0170E: Aucun serveur de noms défini dans /etc/resolv.conf "
MSG_CS[$MSG_NO_NAMESERVER_DEFINED]="!!! CND0170E: Není nastavený žádný nameserver v /etc/resolv.conf"
MSG_DE[$MSG_NO_NAMESERVER_DEFINED]="!!! CND0170E: Kein Nameserver in /etc/resolv.conf definiert"
MSG_PT[$MSG_NO_NAMESERVER_DEFINED]="!!! CND0170E: Nenhum servidor de nomes especificado em /etc/resolv.conf"
MSG_PL[$MSG_NO_NAMESERVER_DEFINED]="!!! CND0170E: Brak zdefiniowanych serwerów nazw (DNS) w pliku /etc/resolv.conf"
MSG_CANT_PING_EXTERNAL_IP=308
MSG_EN[$MSG_CANT_PING_EXTERNAL_IP]="!!! CND0180I: The system can't ping external IP address %1"
MSG_FR[$MSG_CANT_PING_EXTERNAL_IP]="!!! CND0180I: Le système ne peut pas pinguer l'adresse IP externe %1"
MSG_CS[$MSG_CANT_PING_EXTERNAL_IP]="!!! CND0180I: Systém nemůže provést ping test externí IP adresy %1"
MSG_DE[$MSG_CANT_PING_EXTERNAL_IP]="!!! CND0180I: Das System kann die externe IP %1 nicht pingen"
MSG_PT[$MSG_CANT_PING_EXTERNAL_IP]="!!! CND0180I: O sistema não consegue dar ping no IP %1"
MSG_PL[$MSG_CANT_PING_EXTERNAL_IP]="!!! CND0180I: Komenda ping nie może dotrzeć do zewnętrznego adresu IP %1"
MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS=309
MSG_EN[$MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS]="!!! CND0190E: WLAN firmware is missing or cannot be loaded"
MSG_FR[$MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS]="!!! CND0190E: Le firmware pour WLAN est absent ou ne peut pas être chargé"
MSG_CS[$MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS]="!!! CND0190E: Chybí nebo nemohu nahrát WLAN firmware"
MSG_DE[$MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS]="!!! CND0190E: WLAN Firmware fehlt oder kann nicht geladen werden"
MSG_PT[$MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS]="!!! CND0190E: O firmware da rede sem fio está faltando ou não pode ser carregado"
MSG_PL[$MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS]="!!! CND0190E: Brak firmware dla WLAN bądź nie może on zostać załadowany"
MSG_POSSIBLE_MTU_PROBLEMS=310
MSG_EN[$MSG_POSSIBLE_MTU_PROBLEMS]="!!! CND0200W: Maximum possible MTU is %1, but actual MTU on nic %2 is %3"
MSG_FR[$MSG_POSSIBLE_MTU_PROBLEMS]="!!! CND0200W: Le MTU maximum possible est de %1, mais le MTU réel sur la plaque réseau %2 est de %3"
MSG_CS[$MSG_POSSIBLE_MTU_PROBLEMS]="!!! CND0200W: Maximum možného MTU je %1, ale nynější MTU na kartě %2 je %3"
MSG_DE[$MSG_POSSIBLE_MTU_PROBLEMS]="!!! CND0200W: Die maximal ermittelte MTU ist %1, aber die aktuelle MTU an der Netzwerkkarte %2 ist %3"
MSG_PT[$MSG_POSSIBLE_MTU_PROBLEMS]="!!! CND0200W: O MTU máximo é %1, mas o MTU real na placa de rede %2 é %3"
MSG_PL[$MSG_POSSIBLE_MTU_PROBLEMS]="!!! CND0200W: Maksymalne możliwe MTU wynosi %1, lecz aktualnie ustawione na karcie %2 jest %3"
MSG_APIPA_DETECTED=311
MSG_EN[$MSG_APIPA_DETECTED]="!!! CND0210W: APIPA IP address %1 detected on network card %2"
MSG_FR[$MSG_APIPA_DETECTED]="!!! CND0210W: Adresse IP APIPA  %1 détectée sur la carte réseau %2"
MSG_CS[$MSG_APIPA_DETECTED]="!!! CND0210W: APIPA IP adresa %1 detekována na síťové kartě %2"
MSG_DE[$MSG_APIPA_DETECTED]="!!! CND0210W: APIPA IP Adresse %1 wurde an Netzwerkkarte %2 entdeckt"
MSG_PT[$MSG_APIPA_DETECTED]="!!! CND0210W: Endereço IP %1 APIPA detectado na placa de rede %2"
MSG_PL[$MSG_APIPA_DETECTED]="!!! CND0210W: Na karcie %2 przydzielony jest awaryjny automatyczny adres sieciowy (APIPA)"
MSG_NIC_ERRORS=312
MSG_EN[$MSG_NIC_ERRORS]="!!! CND0220W: Serious transmission errors on network interface %1 detected"
MSG_FR[$MSG_NIC_ERRORS]="!!! CND0220W: Erreurs graves de transmission sur l'interface de réseau %1 détectée"
MSG_CS[$MSG_NIC_ERRORS]="!!! CND0220W: Objevily se vážné přenosové chyby v síťovém rozhraní %1 "
MSG_DE[$MSG_NIC_ERRORS]="!!! CND0220W: Ungewöhnlich viele Übertragungsfehler am Interface %1 entdeckt"
MSG_PT[$MSG_NIC_ERRORS]="!!! CND0220W: Erros sérios de transmissão detectados na placa de rede %1"
MSG_PL[$MSG_NIC_ERRORS]="!!! CND0220W: Na urządzeniu %1 wykryto poważne błędy transmisji"
MSG_IPV6_DETECTED=313
MSG_EN[$MSG_IPV6_DETECTED]="!!! CND0230W: IPV6 enabled and may be the reason for network problems"
MSG_FR[$MSG_IPV6_DETECTED]="!!! CND0230W: IPV6 activé"
MSG_CS[$MSG_IPV6_DETECTED]="!!! CND0230W: IPV6 povolené"
MSG_DE[$MSG_IPV6_DETECTED]="!!! CND0230W: IPV6 ist eingeschaltet und kann der Grund für Netzwerkprobleme sein"
MSG_PT[$MSG_IPV6_DETECTED]="!!! CND0230W: IPV6 habilitado"
MSG_PL[$MSG_IPV6_DETECTED]="!!! CND0230W: Włączony protokół IPV6"
MSG_KNETWORKMANAGER_ERROR=314
MSG_EN[$MSG_KNETWORKMANAGER_ERROR]="!!! CND0240E: networkmanager for network configuration enabled but a YAST network card configuration for %1 exist"
MSG_FR[$MSG_KNETWORKMANAGER_ERROR]="!!! CND0240E: le networkmanager pour configuration du réseau est actif, mais il existe une configuration YAST de carte réseau pour %1"
MSG_CS[$MSG_KNETWORKMANAGER_ERROR]="!!! CND0240E: networkmanager pro síťovou konfiguraci je povolen, ale existuje YAST konfigurace síťové karty pro %1 "
MSG_DE[$MSG_KNETWORKMANAGER_ERROR]="!!! CND0240E: networkmanager wird für die Netzwerkkonfiguration benutzt aber eine YAST Netzwerkkartenkonfiguration für %1 existiert"
MSG_E[$MSG_KNETWORKMANAGER_ERROR]="!!! CND0240E: networkmanager for network configuration enabled but a YAST network card configuration for %1 exist"
MSG_PL[$MSG_KNETWORKMANAGER_ERROR]="!!! CND0240E: networkmanager jest włączony ale jednocześnie karta sieciowa %1 jest skonfigurowana poprzez YAST"
MSG_CANT_LOOKUP_EXTERNAL_DNS=315
MSG_EN[$MSG_CANT_LOOKUP_EXTERNAL_DNS]="!!! CND0250E: The system can't lookup external DNS name %1"
MSG_FR[$MSG_CANT_LOOKUP_EXTERNAL_DNS]="!!! CND0250E: Le système ne peut pas rechercher le DNS externe %1 "
MSG_CS[$MSG_CANT_LOOKUP_EXTERNAL_DNS]="!!! CND0250E: System nemůže vyhledat externí DNS jméno %1"
MSG_DE[$MSG_CANT_LOOKUP_EXTERNAL_DNS]="!!! CND0250E: Das System kann den externen Namen %1 nicht auflösen"
MSG_PT[$MSG_CANT_LOOKUP_EXTERNAL_DNS]="!!! CND0250E: O sistema não consegue resolver o nome DNS externo %1"
MSG_PL[$MSG_CANT_LOOKUP_EXTERNAL_DNS]="!!! CND0250E: Nie można odpytać zewnętrznego serwera nazw (DNS) %1"
MSG_NDISWRAPPER_PROB=316
MSG_EN[$MSG_NDISWRAPPER_PROB]="!!! CND0260E: ndiswrapper for %1 can't be used in parallel with linux native driver %2"
MSG_FR[$MSG_NDISWRAPPER_PROB]="!!! CND0260E: ndiswrapper pour %1 ne peut pas être utilisé en parallèle avec le pilote Linux natif %2"
MSG_CS[$MSG_NDISWRAPPER_PROB]="!!! CND0260E: ndiswrapper pro %1 nemůže být použit paralelně s linuxovým vlastním ovladačem %2"
MSG_DE[$MSG_NDISWRAPPER_PROB]="!!! CND0260E: ndiswrapper für %1 kann nicht gemeinsam mit dem linux Treiber %2 benutzt werden"
MSG_PT[$MSG_NDISWRAPPER_PROB]="!!! CND0260E: ndiswrapper para %1 não pode ser usado junto com o driver nativo do Linux %2"
MSG_PL[$MSG_NDISWRAPPER_PROB]="!!! CND0260E: ndsiwrpaper dla %1 nie może być użyty razem z natywnym sterownikiem dla linuxa %2"
MSG_NDISWRAPPER_FW_PROB=317
MSG_EN[$MSG_NDISWRAPPER_FW_PROB]="!!! CND0270E: Used windows driver %1 was either not installed completely (e.g. sys files are missing)\n--- or is from a wrong windows version (e.g. Win 98 instead of XP)"
MSG_FR[$MSG_NDISWRAPPER_FW_PROB]="!!! CND0270E: Le pilote Windows %1 n'est soit pas installé complètement (fichiers système manquants, par exemple) \ n --- ou provient d'une version incorrecte de Windows (par exemple, 98 au lieu de Win XP)"
MSG_CS[$MSG_NDISWRAPPER_FW_PROB]="!!! CND0270E: Použitý windows ovladč %1 je neúplně nainstalován (např. chybí sys soubory)\n--- nebo je ze špatné windows verzi (např. Win 98 namísto XP)"
MSG_DE[$MSG_NDISWRAPPER_FW_PROB]="!!! CND0270E: Der verwendete Windowstreiber %1 wurde entweder nicht vollständig installiert (Treiberbestandteile fehlen z.B. sys Dateien)\n--- oder ist von der falschen Windows-Version (z.B. Win 98 statt XP)"
MSG_PT[$MSG_NDISWRAPPER_FW_PROB]="!!! CND0270E: O driver Windows %1 usado não foi instalado completamente (p. ex. arquivos .sys faltando)\n--- ou são de uma versão windows incompatível (p. ex. Win 98 em vez de XP)"
MSG_PL[$MSG_NDISWRAPPER_FW_PROB]="!!! CND0270E: Używany sterownik Windows %1 nie został w całości zainstalowany (np. brak niektórych plików systemowych)\n--- bądź jest ze złej wersji Windows (np. Win98 zamiast XP)"
MSG_NDISWRAPPER_ARCH_PROB=318
MSG_EN[$MSG_NDISWRAPPER_ARCH_PROB]="!!! CND0280E: Incompatible windows driver architecture of %1 and Linux architecture (32 bit and 64 bit architecture mixed)"
MSG_FR[$MSG_NDISWRAPPER_ARCH_PROB]="!!! CND0280E: Les architectures du pilote Windows de %1 et de Linux sont incompatibles (mélange d'architectures 32 bits et 64 bits)"
MSG_CS[$MSG_NDISWRAPPER_ARCH_PROB]="!!! CND0280E: Nekompatibilní architektura windows ovladače %1 a Linux architektury (32 bit a 64 bit smíchané architektury)"
MSG_DE[$MSG_NDISWRAPPER_ARCH_PROB]="!!! CND0280E: Inkompatible Windowstreiber Architektur von %1 und Linux Architektur (32 Bit und 64 Bit Architektur gemischt)"
MSG_PT[$MSG_NDISWRAPPER_ARCH_PROB]="!!! CND0280E: Arquiteturas incompatíveis dos drivers Windows %1 e Linux (32 bits e 64 bits misturadas)"
MSG_PL[$MSG_NDISWRAPPER_ARCH_PROB]="!!! CND0280E: Wersja sterowników Windows %1 niekompatybilna z architekturą Linuxa (Wymieszana architektura 32- i 64 bitowa)"
MSG_NO_NIC_CONFIG_FOUND=319
MSG_EN[$MSG_NO_NIC_CONFIG_FOUND]="!!! CND0290E: No network configuration found for interface %1"
MSG_FR[$MSG_NO_NIC_CONFIG_FOUND]="!!! CND0290E: Configuration réseau introuvable pour l'interface %1"
MSG_CS[$MSG_NO_NIC_CONFIG_FOUND]="!!! CND0290E: Nenašla se žádná síťová konfigurace pro rozhraní %1"
MSG_DE[$MSG_NO_NIC_CONFIG_FOUND]="!!! CND0290E: Keine Netzwerkkonfiguration für Interface %1 gefunden"
MSG_PT[$MSG_NO_NIC_CONFIG_FOUND]="!!! CND0290E: Nenhuma configuração de rede encontrada para a interface %1"
MSG_PL[$MSG_NO_NIC_CONFIG_FOUND]="!!! CND0290E: Nie znaleziono konfiguracji dla urządzenia %1"
MSG_NO_DHCP_FOUND=320
MSG_EN[$MSG_NO_DHCP_FOUND]="!!! CND0300E: No dhcp server found on interface %1"
MSG_FR[$MSG_NO_DHCP_FOUND]="!!! CND0300E: Pas trouvé de serveur dhcp sur l'interface %1"
MSG_CS[$MSG_NO_DHCP_FOUND]="!!! CND0300E: Nenašel se DHCP server found pro rozhraní %1"
MSG_DE[$MSG_NO_DHCP_FOUND]="!!! CND0300E: Keinen dhcp Server am Interface %1 gefunden"
MSG_PT[$MSG_NO_DHCP_FOUND]="!!! CND0300E: Nenhum servidor DHCP encontrado na interface %1"
MSG_PL[$MSG_NO_DHCP_FOUND]="!!! CND0300E: Nie znaleziono serwera DHCP na urządzeniu %1"
MSG_IFUP_CONFIGURED=321
MSG_EN[$MSG_IFUP_CONFIGURED]="!!! CND0310W: Classic network configuration with ifup was detected. Configuration with networkmanager is easier"
MSG_FR[$MSG_IFUP_CONFIGURED]="!!! CND0310W: une configuration classique de réseau par ifup a été détectée. La configuration par networkmanager est beaucoup plus facile"
MSG_CS[$MSG_IFUP_CONFIGURED]="!!! CND0310W: Detekována klasická síťová konfigurace s ifup. Konfigurace s networkmanager-em je mnohem lehčí"
MSG_DE[$MSG_IFUP_CONFIGURED]="!!! CND0310W: Klassische Netzwerkkonfiguration mit ifup wurde entdeckt. Die Konfiguration mit networkmanager ist einfacher"
MSG_PT[$MSG_IFUP_CONFIGURED]="!!! CND0310W: Configuração ifup clássica detectada. A configuração com o networkmanager é bem mais fácil"
MSG_PL[$MSG_IFUP_CONFIGURED]="!!! CND0310W: Wykryto standardową konfigurację sieciową poprzez ifup. Konfiguracja z użyciem networkmanager jest znacznie prostsza."
MSG_WLAN_KILL_SWITCH_ON=322
MSG_EN[$MSG_WLAN_KILL_SWITCH_ON]="!!! CND0320E: WLAN turned off by hardware or software switch"
MSG_FR[$MSG_WLAN_KILL_SWITCH_ON]="!!! CND0320E: WLAN désactivé par interrupteur materiel ou logiciel"
MSG_CS[$MSG_WLAN_KILL_SWITCH_ON]="!!! CND0320E: WLAN je vypnuté hardwarovám nebo softwarovým přepínačem/switch-em"
MSG_DE[$MSG_WLAN_KILL_SWITCH_ON]="!!! CND0320E: WLAN ist mit dem Hardware oder Software Switch ausgeschaltet"
MSG_PT[$MSG_WLAN_KILL_SWITCH_ON]="!!! CND0320E: Rede sem fio desligada por interruptor de hardware ou software"
MSG_PL[$MSG_WLAN_KILL_SWITCH_ON]="!!! CND0320E: Sieć bezprzewodowa została wyłączona z poziomu sprzętowego bądź programowego"
MSG_WLAN_AUTH_PROBS=323
MSG_EN[$MSG_WLAN_AUTH_PROBS]="!!! CND0330E: WLAN credential problems exist on interface %1"
MSG_FR[$MSG_WLAN_AUTH_PROBS]="!!! CND0330E: Des problèmes d'authenticité du WLAN existent sur l'interface %1"
MSG_CS[$MSG_WLAN_AUTH_PROBS]="!!! CND0330E: WLAN potíže existují na rozhraní %1"
MSG_DE[$MSG_WLAN_AUTH_PROBS]="!!! CND0330E: Es existierern Schlüsselprobleme am Interface %1"
MSG_PT[$MSG_WLAN_AUTH_PROBS]="!!! CND0330E: Problema de credenciais de rede sem fio na interface %1"
MSG_PL[$MSG_WLAN_AUTH_PROBS]="!!! CND0330E: Na urządzeniu %1 istnieje problem z uwierzytelnianiem WLAN"
MSG_NO_DHCP_DETECTED=324
MSG_EN[$MSG_NO_DHCP_DETECTED]="!!! CND0350W: dhcp server may not available on interface %1"
MSG_FR[$MSG_NO_DHCP_DETECTED]="!!! CND0350W: Serveur DHCP peut être indisponibles sur l' interface %1"
MSG_CS[$MSG_NO_DHCP_DETECTED]="!!! CND0350W: dhcp server může být nedostupný na rozhraní %1"
MSG_DE[$MSG_NO_DHCP_DETECTED]="!!! CND0350W: Ein dhcp Server scheint nicht am Interface %1 zu existieren"
MSG_PT[$MSG_NO_DHCP_DETECTED]="!!! CND0350W: O servidor DHCP pode não estar disponível na interface %1"
MSG_PL[$MSG_NO_DHCP_DETECTED]="!!! CND0350W: DHCP serwer może nie być dostępny dla urządzenia %1"
MSG_WLAN_WIRED_ONLINE=325
MSG_EN[$MSG_WLAN_WIRED_ONLINE]="!!! CND0360E: Wireless connection tested with an existing wired connection on interface %1. Unplug the cable and execute the script again"
MSG_FR[$MSG_WLAN_WIRED_ONLINE]="!!! CND0360E: Connexion sans fil testée avec une connexion filaire existante sur interface %1. Débranchez le câble d'interface et exécutez le script à nouveau"
MSG_CS[$MSG_WLAN_WIRED_ONLINE]="!!! CND0360E: Bezdrátobé připojení ostestováno s existujícím drátovým připojením  na rozhraní %1. Odpojte kabel a opět spusťte skript"
MSG_DE[$MSG_WLAN_WIRED_ONLINE]="!!! CND0360E: Eine drahtlose Verbindung wurde getestet obwohl eine kabelgebundene Verbindung am Interface %1 existiert . Das Netzwerkkabel ausstecken und das Script noch einmal starten"
MSG_PT[$MSG_WLAN_WIRED_ONLINE]="!!! CND0360E: Conexão sem fio testada com uma conexão cabeada na interface %1. Desconecte o cabo e execute o script novamente"
MSG_PL[$MSG_WLAN_WIRED_ONLINE]="!!! CND0360E: Testy połączenia bezprzewodowego przeprowadzone z istniejącym połączeniem sieciowym na urządzeniu %1. Proszę odłącz kabel sieciowy i uruchom skrypt ponownie"
MSG_CANT_PING_EXTERNAL_DNS=326
MSG_EN[$MSG_CANT_PING_EXTERNAL_DNS]="!!! CND0370I: The system can't ping external DNS name %1"
MSG_FR[$MSG_CANT_PING_EXTERNAL_DNS]="!!! CND0370I: Le système ne peut pas pinger le nom DNS externe %1"
MSG_CS[$MSG_CANT_PING_EXTERNAL_DNS]="!!! CND0370I: System nemůže provést ping test pro externí DNS jméno %1"
MSG_DE[$MSG_CANT_PING_EXTERNAL_DNS]="!!! CND0370I: Das System kann den externen DNS Namen %1 nicht pingen"
MSG_PT[$MSG_CANT_PING_EXTERNAL_DNS]="!!! CND0370I: O sistema não consegue dar ping no nome DNS externo %1"
MSG_PL[$MSG_CANT_PING_EXTERNAL_DNS]="!!! CND0370I: Serwer nazw %1 niedostępny z użyciem komendy ping"
MSG_WLAN_NO_SCAN=327
MSG_EN[$MSG_WLAN_NO_SCAN]="!!! CND0380E: No WLANs detected on interface %1. Hardware and/or driver not configured properly"
MSG_FR[$MSG_WLAN_NO_SCAN]="!!! CND0380E: Pas de WLANs détectés sur l'interface %1. Le matériel et/ou le pilote sont mal configurés"
MSG_CS[$MSG_WLAN_NO_SCAN]="!!! CND0380E: Nedetkováno žádné WLAN na rozhraní %1. Hardware a/nebo ovladač není správně nakonfigurovno"
MSG_DE[$MSG_WLAN_NO_SCAN]="!!! CND0380E: Es wurden keine WLANs am Interface %1 gefunden. Die Hardware und/oder Treiber ist nicht richtig konfiguriert"
MSG_PT[$MSG_WLAN_NO_SCAN]="!!! CND0380E: Nenhuma rede local sem fio detectada na interface %1. Hardware e/ou driver configurados erroneamente"
MSG_PL[$MSG_WLAN_NO_SCAN]="!!! CND0380E: Nie wykryto żadnych sieci bezprzewodowych na urządzeniu %1. Urządzeniu i/lub sterownik nie zostały prawidłowo skonfigurowane"
MSG_HW_NO_ACTIVE=328
MSG_EN[$MSG_HW_NO_ACTIVE]="!!! CND0390E: No loaded module detected for interface %1"
MSG_FR[$MSG_HW_NO_ACTIVE]="!!! CND0390E: Aucun module chargé n 'est détecté pour l'interface %1"
MSG_CS[$MSG_HW_NO_ACTIVE]="!!! CND0390E: Není detekován žádný nahraný modul pro rozhraní %1"
MSG_DE[$MSG_HW_NO_ACTIVE]="!!! CND0390E: Kein Module am Interface %1 geladen"
MSG_PT[$MSG_HW_NO_ACTIVE]="!!! CND0390E: Nenhum módulo carregado detectado para a interface %1"
MSG_PL[$MSG_HW_NO_ACTIVE]="!!! CND0390E: Brak załadowanego modułu dla urządzenia %1"
MSG_HW_SOME_INACTIVE=329
MSG_EN[$MSG_HW_SOME_INACTIVE]="!!! CND0400W: Alternate modules %1 detected for interface %2"
MSG_FR[$MSG_HW_SOME_INACTIVE]="!!! CND0400W: Modules alternatifs %1 détectés pour l'interface %2"
MSG_CS[$MSG_HW_SOME_INACTIVE]="!!! CND0400W: Alternativní modul %1 detekován pro rozhraní %2"
MSG_DE[$MSG_HW_SOME_INACTIVE]="!!! CND0400W: Es existieren weitere mögliche Module %1 für Interface %2"
MSG_PT[$MSG_HW_SOME_INACTIVE]="!!! CND0400W: Módulo alternativo %1 detectado para a interface %2"
MSG_PL[$MSG_HW_SOME_INACTIVE]="!!! cnd0400W: Alternatywne moduły %1 zostały wykryte dla urządzenia %2"
MSG_NAMESERVER_NOT_VALID=330
MSG_EN[$MSG_NAMESERVER_NOT_VALID]="!!! CND0410E: Configured nameserver with IP %1 is no nameserver"
MSG_FR[$MSG_NAMESERVER_NOT_VALID]="!!! CND0410E: Le DNS configuré par l' IP %1 n'est pas un serveur DNS"
MSG_CS[$MSG_NAMESERVER_NOT_VALID]="!!! CND0410E: Nakonfigurovaný nameserver s IP %1 není nameserver"
MSG_DE[$MSG_NAMESERVER_NOT_VALID]="!!! CND0410E: Der konfigurierte Nameserver mit der IP %1 ist kein Nameserver"
MSG_PT[$MSG_NAMESERVER_NOT_VALID]="!!! CND0410E: Servidor de nomes configurado com IP %1 não é um servidor de nomes"
MSG_PL[$MSG_NAMESERVER_NOT_VALID]="!!! CND0410E: Serwer nazw skonfigurowany pod adresem %1 nie jest właściwym serwerem nazw"
MSG_NAMESERVER_PROBLEM_UNKNOWN=331
MSG_EN[$MSG_NAMESERVER_PROBLEM_UNKNOWN]="!!! CND0420E: There exists a problem with configured nameserver with IP %1"
MSG_FR[$MSG_NAMESERVER_PROBLEM_UNKNOWN]="!!! CND0420E: Il y a un problème avec le serveur DNS configuré avec IP %1"
MSG_CS[$MSG_NAMESERVER_PROBLEM_UNKNOWN]="!!! CND0420E: Je problém s nakonfigurovaným nameserver-em s IP %1"
MSG_DE[$MSG_NAMESERVER_PROBLEM_UNKNOWN]="!!! CND0420E: Es gibt ein Problem mit dem konfigurierten Nameserver mit der IP %1"
MSG_PT[$MSG_NAMESERVER_PROBLEM_UNKNOWN]="!!! CND0420E: Existe um problema com o servidor de nomes configurado com IP %1"
MSG_PL[$MSG_NAMESERVER_PROBLEM_UNKNOWN]="!!! CND0420E: Wykryto problem z serwerem nazw skonfigurowanym pod adresem %1"
MSG_NWELIZA_UNAVAILABLE=332
MSG_EN[$MSG_NWELIZA_UNAVAILABLE]="!!! CND0430I: NWEliza doesn't support this Linux distribution"
MSG_FR[$MSG_NWELIZA_UNAVAILABLE]="!!! CND0430I: NWEliza ne supporte pas cette distribution Linux"
MSG_CS[$MSG_NWELIZA_UNAVAILABLE]="!!! CND0430I: NWEliza nepodporuje tuto Linux distribuci"
MSG_DE[$MSG_NWELIZA_UNAVAILABLE]="!!! CND0430I: NWEliza unterstützt diese Linux distribution nicht"
MSG_PT[$MSG_NWELIZA_UNAVAILABLE]="!!! CND0430I: NWEliza não suporta essa distribuição Linux"
MSG_PL[$MSG_NWELIZA_UNAVAILABLE]="!!! CND0430I: NWEliza nie jest wspierana dla tej dystrybucji"
MSG_DISTRO_NOT_SUPPORTED=333
MSG_EN[$MSG_DISTRO_NOT_SUPPORTED]="!!! CND0440E: This distribution is not supported"
MSG_FR[$MSG_DISTRO_NOT_SUPPORTED]="!!! CND0440E: Cette distribution n'est pas supportée"
MSG_CS[$MSG_DISTRO_NOT_SUPPORTED]="!!! CND0440E: Tato distribuce není podporována"
MSG_DE[$MSG_DISTRO_NOT_SUPPORTED]="!!! CND0440E: Diese Distribution wird leider nicht unterstützt"
MSG_PT[$MSG_DISTRO_NOT_SUPPORTED]="!!! CND0440E: Essa distribuição não é suportada"
MSG_PL[$MSG_DISTRO_NOT_SUPPORTED]="!!! CND0440E: Ta dystrybucja nie jest wspierana"
MSG_CHECK_KEYS=334
MSG_EN[$MSG_CHECK_KEYS]="!!! CND0450W: WLAN key masquerading is not fully tested on this distribution. Please check output file %1 for visible WLAN keys and masquerade them manually"
MSG_FR[$MSG_CHECK_KEYS]="!!! CND0450W: Le 'masquerading' WLAN n'est pas entièrement testé sur cette distribution. S'il vous plaît vérifiez sur le fichier de sortie %1 les clés WLAN visibles et 'mascaradez' manuellement"
MSG_CS[$MSG_CHECK_KEYS]="!!! CND0450W: WLAN masquerading klíč není zcela otestován na této distribuci. Prosím, zkontrolujte výsledný soubor %1 pro viditelné WLAN klíče a zamaskujte je manuálně"
MSG_DE[$MSG_CHECK_KEYS]="!!! CND0450W: WLAN Schlüsselmaskierung ist nicht vollständig auf dieser Distribution getestet. Bitte das Ausgabefile %1 nach sichtbaren WLAN Schlüsseln absuchen und manuell maskieren"
MSG_PT[$MSG_CHECK_KEYS]="!!! CND0450W: O mascaramento da chave de rede sem fio não está completamente testado nessa distribuição. Cheque o arquivo %1 e mascare chaves visíveis manualmente"
MSG_PL[$MSG_CHECK_KEYS]="!!! CND0450W: Maskowania kluczy WLAN dla tej dystrybucji nie zostało w pełni przetestowane. Proszę sprawdź plik z wynikami %1 czy są tam zapisane klucze WLAN i zamaskuj je ręcznie."
MSG_NO_ANALYSIS_AS_USER=335
MSG_EN[$MSG_NO_ANALYSIS_AS_USER]="!!! CND0460I: Analysis of %1 only possible if script is invoked as root"
MSG_FR[$MSG_NO_ANALYSIS_AS_USER]="!!! CND0460I: L'analyse de %1 est seulement possible si le script est invoqué en tant que root"
MSG_CS[$MSG_NO_ANALYSIS_AS_USER]="!!! CND0460I: Analýza %1 je možná pouze pokud je skript spuštěn jako root"
MSG_DE[$MSG_NO_ANALYSIS_AS_USER]="!!! CND0460I: Analyse von %1 nur möglich wenn das Script als root aufgerufen wird"
MSG_PT[$MSG_NO_ANALYSIS_AS_USER]="!!! CND0460I: Análise de %1 só é possível se o script for executado como root"
MSG_PL[$MSG_NO_ANALYSIS_AS_USER]="!!! CND0460I: Analiza %1 jest możliwa tylko jeżeli skrypt został uruchomiony jako użytkownik root"
MSG_ANALYSIS_AS_USER=336
MSG_EN[$MSG_ANALYSIS_AS_USER]="!!! CND0470I: Reduced analysis capability and less network information because script was not invoked as root"
MSG_FR[$MSG_ANALYSIS_AS_USER]="!!! CND0470I: Capacité d'analyse réduite et moins d'informations de réseau parce que le script n'a pas été invoqué en tant que root"
MSG_CS[$MSG_ANALYSIS_AS_USER]="!!! CND0470I: Analýza redukována a méně síťových informací, protože skript nebyl spuštěn jako root"
MSG_DE[$MSG_ANALYSIS_AS_USER]="!!! CND0470I: Reduzierte Analysefähigkeit und weniger Netzwerkinformationen da das Script nicht als root ausgeführt wurde"
MSG_PT[$MSG_ANALYSIS_AS_USER]="!!! CND0470I: Capacidade reduzida de análise e menos informações de rede porque o script não foi executado como root"
MSG_PL[$MSG_ANALYSIS_AS_USER]="!!! CND0470I: Ponieważ skrypt nie został uruchomiony z prawami roota wiarygodność analizy oraz ilość informacji zostały obniżone"
MSG_MISSING_LINK=337
MSG_EN[$MSG_MISSING_LINK]="!!! CND0480W: No link detected on interface %1"
MSG_FR[$MSG_MISSING_LINK]="!!! CND0480W: Pas de lien détecté sur l'interface %1"
MSG_CS[$MSG_MISSING_LINK]="!!! CND0480W: Nneí deetekováno žádné spojení na rozhraní %1"
MSG_DE[$MSG_MISSING_LINK]="!!! CND0480W: Es wurde kein Linksignal auf Interface %1 entdeckt"
MSG_PT[$MSG_MISSING_LINK]="!!! CND0480W: Nenhuma conexão detectada na interface %1"
MSG_PL[$MSG_MISSING_LINK]="!!! CND0480W: Brak połączenia na urządzeniu %1"
MSG_WLAN_NO_SSID_IN_SCAN_FOUND=338
MSG_EN[$MSG_WLAN_NO_SSID_IN_SCAN_FOUND]="!!! CND0490E: No access point with your SSID detected on interface %1"
MSG_FR[$MSG_WLAN_NO_SSID_IN_SCAN_FOUND]="!!! CND0490E: Aucun point d'accès avec votre SSID détecté sur l'interface %1"
MSG_CS[$MSG_WLAN_NO_SSID_IN_SCAN_FOUND]="!!! CND0490E: Není detekován žádny přístupový bod s vašim SSID  na rozhraní %1"
MSG_DE[$MSG_WLAN_NO_SSID_IN_SCAN_FOUND]="!!! CND0490E: Kein Accesspoint mit der benutzen SSID auf dem Interface %1 gefunden"
MSG_PT[$MSG_WLAN_NO_SSID_IN_SCAN_FOUND]="!!! CND0490E: Nenhum ponto de acesso com sua SSID detectado na interface %1"
MSG_PL[$MSG_WLAN_NO_SSID_IN_SCAN_FOUND]="!!! CND0490E: Nie znaleziono punktu dostępowego z podaną nazwą (SSID) dla urządzenia %1"
MSG_SSID_SAME_CHANNEL=339
MSG_EN[$MSG_SSID_SAME_CHANNEL]="!!! CND0500W: Channel %1 used by your accesspoint is also used by %2 other access points"
MSG_FR[$MSG_SSID_SAME_CHANNEL]="!!! CND0500W: Canal %1 utilisé par votre point d'accès est également utilisée par %2 autres points d'accès"
MSG_CS[$MSG_SSID_SAME_CHANNEL]="!!! CND0500W: Kanál %1 použitý vašim přístupovým bodem je také použit %2 ostatními přístup. body"
MSG_DE[$MSG_SSID_SAME_CHANNEL]="!!! CND0500W: Der Kanal %1, der vom eigenen Accesspoint benutzt wird, wird von %2 weiteren Accesspoints genutzt"
MSG_PT[$MSG_SSID_SAME_CHANNEL]="!!! CND0500W: O canal %1 usado por seu ponto de acesso também é usado por %2 outros pontos de acesso"
MSG_PL[$MSG_SSID_SAME_CHANNEL]="!!! CND0500W: Kanał %1 używany przez Twój punkt dostępowy jest wykorzystywany również %2 innych punktów"
MSG_SSID_INTERFERENCES=340
MSG_EN[$MSG_SSID_INTERFERENCES]="!!! CND0510W: Channel %1 used by your accesspoint interferes with %2 adjacent access points"
MSG_FR[$MSG_SSID_INTERFERENCES]="!!! CND0510W: Canal %1 utilisé par votre point d'accès interfère avec %2 des points d'accès adjacents"
MSG_CS[$MSG_SSID_INTERFERENCES]="!!! CND0510W: Kanál %1 použitý vašim přístupovým bodem se míchá s %2 sousedícími přístup. body"
MSG_DE[$MSG_SSID_INTERFERENCES]="!!! CND0510W: Der Kanal %1, der vom eigenen Accesspoint benutzt wird, wird von %2 benachbarten Access Points überlagert"
MSG_PT[$MSG_SSID_INTERFERENCES]="!!! CND0510W: O canal %1 usado por seu ponto de acesso interfere com %2 pontos de acesso adjacentes"
MSG_PL[$MSG_SSID_INTERFERENCES]="!!! CND0510W: Kanał %1 używany przez twój punkt dostępowy interferuje z %2 innymi punktami dostępowymi"
MSG_NO_WPA_SUPPLICANT_ACTIVE=341
MSG_EN[$MSG_NO_WPA_SUPPLICANT_ACTIVE]="!!! CND0520W: wpa_supplicant is not active"
MSG_FR[$MSG_NO_WPA_SUPPLICANT_ACTIVE]="!!! CND0520W: Le wpa_supplicant n'est pas actif"
MSG_CS[$MSG_NO_WPA_SUPPLICANT_ACTIVE]="!!! CND0520W: wpa_supplicant není aktivní"
MSG_DE[$MSG_NO_WPA_SUPPLICANT_ACTIVE]="!!! CND0520W: wpa_supplicant ist nicht aktiv"
MSG_PT[$MSG_NO_WPA_SUPPLICANT_ACTIVE]="!!! CND0520W: wpa-supplicant não está ativo"
MSG_PL[$MSG_NO_WPA_SUPPLICANT_ACTIVE]="!!! CND0520W: wpa_supplicant nie jest aktywny"
MSG_ENL80211L=342
MSG_EN[$MSG_ENL80211L]="!!! CND0530E: Module %1 requires WIRELESS_WPA_DRIVER='wext' to be configured"
MSG_DE[$MSG_ENL80211L]="!!! CND0530E: Module %1 erfordert die Konfiguration von WIRELESS_WPA_DRIVER='wext'"
MSG_NIC_DROPPED=343
MSG_EN[$MSG_NIC_DROPPED]="!!! CND0540W: Messages dropped on network interface %1"
MSG_DE[$MSG_NIC_DROPPED]="!!! CND0540W: Messages wurden am Netzwerkinterface %1 verworfen"
MSG_NO_NIC_FOUND_WARNING=344
MSG_EN[$MSG_NO_NIC_FOUND_WARNING]="!!! CND0550W: Unable to detect USB network card for the selected connection type"
MSG_DE[$MSG_NO_NIC_FOUND_WARNING]="!!! CND0550W: Für den gewählten Netzwerkverbindungstyp konnte keine USB Netzwerkarte gefunden werden"
MSG_INVALID_SSID=345
MSG_EN[$MSG_INVALID_SSID]="!!! CND0560E: Invalid characters in SSIDs detected"
MSG_DE[$MSG_INVALID_SSID]="!!! CND0560E: Es befinden sich ungültige Zeichen in der SSID"

#################################################################################
# Debug helper
#################################################################################

function debug() { # message
   if [[ $DEBUG == "on" ]];  then
      echo "@@@ $1 $2 $3 $4 $5 $6 $7 $8 $9 ${10}"
   fi
}

function state() { # message
   echo "${1}${2}${3}${4}${5}${6}${7}${8}${9}${10}" >> $STATE
}

########################################################################
#
# --- Check if a command was detected on the system 
#
########################################################################

function isCommandAvailable() {		# $1: command

      local ucCmd	  
      local rc 
      ucCMD=`echo $1 | perl -e "print uc(<>);"`
   
      if [[ "${!ucCMD}" == "" ]]; then
	 rc=1
      else
	 rc=0
      fi

      return $rc

}

#################################################################################
# message & console handling
#################################################################################

# --- Writes a message to the console without an NL

function writeToConsoleNoNL() {   # messagenumber
   local msg
   msg=`getLocalizedMessage $*`
   if [[ $GUI -eq 0 ]]; then
	   echo -ne $msg >> /dev/tty
   else
	   echo -ne $msg >> $CONSOLE_RESULT
	   echo -ne $msg
   fi
}

# --- Writes a message to the console

function writeToConsole() {   # messagenumber
   local msg
   msg=`getLocalizedMessage $*`
   if [[ $GUI -eq 0 ]]; then
	   echo -e $msg >> /dev/tty
   else
	   echo -e $msg >> $CONSOLE_RESULT
	   echo -e $msg
   fi
}

# --- Creates a progress bar on the console

function processingMessage() { #number #maxnumber #activity
   local c
   local ip
   local p
   local m

   if (( $GUI )); then
	return
   fi

   m=$1
   echo -ne "\r                                               \r" >> /dev/tty
   if [[ $m -ge 0 ]]; then
      let p=$m*100/$2
      echo -n "($p%) "
   fi
}

function progress() {

   if [ "$1" != "" ]; then 
      echo -ne "\bDone " 
   fi

   PROGRESS_CHARS="|/-\\"
   if [[ $PROGRESS_CHAR == "" || $PROGRESS_I > "3" ]]; then
      PROGRESS_I=0
   fi
   PROGRESS_CHAR=${PROGRESS_CHARS:$PROGRESS_I:1}
   let PROGRESS_I++
   echo -en "\b$PROGRESS_CHAR"
   }

# ---Writes a messages to the NWEliza log and console

function writeToEliza() {   # messagenumber
   local severity

   local msg
   msg=`getTargetMessage $*`
   echo -e $msg >> "$ELIZA_RESULT"
   msg=`getLocalizedMessage $*`
   if [[ $GUI -eq 0 ]]; then
	echo -e $msg >> /dev/tty
   else
	echo -e $msg
   fi

   severity=`echo $msg | cut -d " " -f 2`

   if [[ `echo $severity | $EGREP "CND[0-9]+E"` ]]; then
      let askEliza_error=$askEliza_error+1
   fi

   if [[ `echo $severity | $EGREP "CND[0-9]+W"` ]]; then
      let askEliza_warning=$askEliza_warning+1
   fi
}

# ---Writes a messages to the NWEliza log

function writeToElizaOnly() {                              # messagenumber
   local msg
   msg=`getTargetMessage $*`
   echo -e $msg >> "$ELIZA_RESULT"
}

# checks whether there exists support for the given language
#
# returns 1 for yes and 0 for no

function isLanguageSupported() {

   LANG_EXT=`echo $LANG | tr '[:lower:]' '[:upper:]'`
   LANG_SUFF=${LANG_EXT:0:2}

   msgVar="MSG_${LANG_SUFF}"

   if [[ ${!msgVar} != "" ]]; then
      return 1
   else
      return 0
   fi
}

# checks whether there exists support for the given language and the os language is not english
#
# returns 1 for yes and 0 for no

function isLanguageSupportedAndNotEnglish() {

   LANG_EXT=`echo $LANG | tr '[:lower:]' '[:upper:]'`
   LANG_SUFF=${LANG_EXT:0:2}
   if [[ $LANG_SUFF == "EN" ]]; then
      return 0
   fi

   msgVar="MSG_${LANG_SUFF}"

   if [[ ${!msgVar} != "" ]]; then
      return 1
   else
      return 0
   fi
}

# --- Helper function to extract the message text in German or English and insert message parameters

function getLocalizedMessage() { # messageNumber parm1 parm2

   msg=`getMessageText L $@`
   echo $msg
}

# get message for target forum

function getTargetMessage() { # messageNumber parm1 parm2

   if (( $CND_INTERNATIONAL_POST )); then
      msg=`getMessageText D $@`
   else
      msg=`getMessageText L $@`
   fi
   echo $msg
}

function getMessageText() {         # languageflag messagenumber parm1 parm2 ...
   local msg
   local p
   local i
   local s

   if [[ $1 == "D" ]]; then
      msg=${MSG_EN[$2]};             # default is english
   else

      LANG_EXT=`echo $LANG | tr '[:lower:]' '[:upper:]'`
      LANG_SUFF=${LANG_EXT:0:2}

      msgVar="MSG_${LANG_SUFF}"

      if [[ ${!msgVar} != "" ]]; then
         msgVar="$msgVar[$2]"
         msg=${!msgVar}
         if [[ $msg == "" ]]; then               # no translation found
            msg=${MSG_EN[$2]};                      # fallback into english
         fi

      else
         msg=${MSG_EN[$2]};                      # default is english
      fi
   fi

   for (( i=3; $i <= $#; i++ )); do              # substitute all message parameters
      p="${!i}"
      let s=$i-2
      s="%$s"
      msg=`echo $msg | sed 's!'$s'!'$p'!'`	# have to use explicit command name 
   done
   msg=`echo $msg | perl -p -e "s/%[0-9]+//g"`      # delete trailing %n definitions
   echo $msg
}

#################################################################################
# --- Check whether pings are possible
#
# --- Ping google dns with it's IP address
# --- return 1 if ip ping failed
# --- return 0 otherwise
#
#################################################################################

function checkIPPings() {

   debug ">>checkIPPings"

   local I
   local PING_RES
   local C
   local rc=0

   MY_IPS="8.8.8.8"

   for I in $MY_IPS; do
      C=`$PING -c 3 -W 3 $I 2>&1`
      PING_RES=`echo $C | $GREP " 0%"`
      pingRC=$?

      if [[ $pingRC == 0 ]]; then
      	 break      
      fi
   done

   if [[ $pingRC != 0 ]]; then
      writeToEliza $MSG_CANT_PING_EXTERNAL_IP $I
      let rc=1
   fi

  state "PNG:$rc"
  debug "<<checkIPPings $rc"

return $rc
}

#################################################################################
# --- Execute ping tests
#
# --- Ping www.google.com with it's IP address and dns name
#################################################################################

function pingTests() {
   local I
   local PING_RES
   local C

   MY_IPS="8.8.8.8"

   for I in $MY_IPS; do
      C=`$PING -c 3 -W 3 $I 2>&1`
      PING_RES=`echo $C | $GREP " 0%"`
      pingRC=$?

      if [[ $pingRC == 0 ]]; then
      	 break      
      fi
   done

   if [[ $pingRC == 0 ]]; then
      echo "Ping of $I OK"
   else
      echo "Ping of $I failed"
   fi

   MY_IPS="www.google.com"

   for I in $MY_IPS; do
      C="$PING -c 3 -W 3 $I"
      PING_RES=`$C | $GREP " 0%"`

      if [[ -z $PING_RES ]]; then
         echo "Ping of $I failed"
      else
         echo "Ping of $I OK"
      fi
   done
return
}

#################################################################################
# --- Execute dhcp tests
#
# --- execute dhcpcd-test against interfaces
#################################################################################

function dhcpTests() {
   local i
   local C
   local R

   if [[ $DISTRO == $SUSE ]]; then
	  if (( $USE_ROOT )); then

		if [[ -z $1 ]]; then

			i=1
			while [[ $i -le $INTERFACE_NO ]]; do
				if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]] ||
                    [[ $CONNECTION == $CONNECTION_WRD && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRD ]]; then
         #            C=`$DHCPCD_TEST -t 3 ${INTERFACE_NAME[$i]} 2>/dev/null`
					C=`$DHCPCD -Td -t 3 -NYRG -c /bin/true ${INTERFACE_NAME[$i]} 2>/dev/null`
					R=`echo $C | grep 'offered'`
					if [[ $? == 0 ]]; then
						echo "${INTERFACE_NAME[$i]}: DHCP server available"
					else
						echo "${INTERFACE_NAME[$i]}: No DHCP server detected $C"
					fi
				fi
			let i=i+1
			done
		else
			echo "dhcpcd-test"
		fi
	else
   		writeToEliza $MSG_NO_ANALYSIS_AS_USER "DHCP_availability"
	fi
fi

return
}

#################################################################################
# --- display rfkill results if rfkill is available
#
#################################################################################

function listrfkill() {

   if `isCommandAvailable rfkill`; then

      if [[ -z $1 ]]; then
      	$RFKILL list wifi
      else
	echo "rfkill list wifi"
   fi
fi

return
}

#################################################################################
# check whether dhcp is configured either with a config file or by using networkmanager if there is no IP address
#
# return 0 if no dhcp was configured
# return 1 if dhcp was configured for wired connection
# return 2 if dhcp was configured for wireless connection
#################################################################################

function checkDHCP() {
   local rc=0
   local conf=0
   local C
   local R

   debug ">>checkDHCP"

   if (( ! $CONFIG_READABLE )); then
   		writeToEliza $MSG_NO_ANALYSIS_AS_USER "DHCP_networkmanager_usage"
		return 0
   fi

   C=`$EGREP -i 'NETWORKMANAGER.*=.*yes' /etc/sysconfig/network/config `
   knme=$?

   i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]] ||
            [[ $CONNECTION == $CONNECTION_WRD && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRD ]]; then

         if [[ ${INTERFACE_IP[$i]} == "" ]]; then                                           # no IP address
            fileName="/etc/sysconfig/network/ifcfg-${INTERFACE_NAME[$i]}";

            conf=0
            if [[ -e $fileName ]]; then                                                     # exists config file?
                  C=`$EGREP -i 'BOOTPROTO.*=.*dhcp' $fileName 2>/dev/null`                  # dhcp configured?
                  if [[ $? == 0 ]]; then                                                    # yes
                     conf=1
                  fi
            fi

            if [[ $knme == 0 && $conf == 0 ]] || [[ $knme != 0 && $conf == 1 ]]; then       # dhcp configured
               C=`$DHCPCD_TEST -t 3 ${INTERFACE_NAME[$i]} 2>/dev/null`
               R=`echo $C | $GREP 'offered'`
               if [[ $? == 1 ]]; then
                    writeToEliza $MSG_NO_DHCP_FOUND ${INTERFACE_NAME[$i]}                   # no dhcp found
                    if [[ $CONNECTION == $CONNECTION_WRL ]]; then
                      rc=2
                    else
                      rc=1
                    fi
               fi
            fi
         fi
      fi
      let i=i+1
   done

   state "DHCP:$rc"
   debug "<<checkDHCP $rc"

}

#################################################################################
# --- Execute dns tests
#
# --- Ping www.google.com with it's dns name
# --- return 1 if dns ping didn't get a response
# --- return 2 if dns ping failed because of missing dns
# --- return 0 otherwise
#
#################################################################################

function checkDNS() {

   debug ">>checkDNS"

   local I
   local PING_RES
   local C
   local rc=0
   local name="www.google.com"

# ping: unknown host www.google.com

   C=`$PING -c 1 -W 3 $name 2>&1`
   pingRC=$?

   if [[ $pingRC == 2 ]]; then
      writeToEliza $MSG_CANT_LOOKUP_EXTERNAL_DNS $name
   elif [[ $pingRC == 1 ]]; then
      writeToEliza $MSG_CANT_PING_EXTERNAL_DNS $name
   fi

   state "DNS:$pingRC"
   debug "<<checkDNS $pingRC"

return $pingRC
}

#################################################################################
#
# detect all interfaces available on system with ifconfig and identify wireless interfaces with iwconfig
#
# result: 1 based array
# INTERFACE_NO: number of interfaces detected
# INTERFACE_NAME: name of interface (enx, wly, ethx, wlany, ...)
# INTERFACE_IP: ipaddress of interface (empty if no IP address found)
# INTERFACE_IP6: ipv6 address of interface (empty if no IPV6 address found)
# INTERFACE_MAC: mac address of interface
# INTERFACE_WRL_NO: number of wireless interfaces detect
# INTERFACE_RCV_ERROR: receive errors (%)
# INTERFACE_XMT_ERROR: xmit errors (%)
# INTERFACE_RCV_DROPPED: receive messages dropped (%)
# INTERFACE_XMT_DROPPED: xmit messages dropped (%)
# INTERFACE_TYPE: either $CONNECTION_WRD or $CONNECTION_WRL
# if $INTERFACE_TYPE == $CONNECTION_WRL
# INTERFACE_ESSID: ESSID
# INTERFACE_MODE: mode of interface
# INTERFACE_ACCESS_POINT: access point mac
# INTERFACE_KEY: wireless key
#
# return number of interfaces found for the selected connection type
#
#################################################################################

function detectInterfaces () {
   local q
   local i
   local j
   local k
   local rc
   local interface
   local element
   INTERFACE_NAME=()
   INTERFACE_IP=()
   INTERFACE_MAC=()
   INTERFACE_RCV_ERROR=()
   INTERFACE_XMT_ERROR=()
   INTERFACE_ESSID=()
   INTERFACE_MODE=()
   INTERFACE_AP=()
   INTERFACE_KEY=()
   INTERFACE_TYPE=()
   INTERFACE_WRL_NO=0
   INTERFACE_WRD_NO=0
   INTERFACE_NO=0

   debug ">>detectInterfaces"

#eth0      Link encap:Ethernet  HWaddr 00:1E:37:21:38:F8
#          inet addr:192.168.0.4  Bcast:192.168.0.255  Mask:255.255.255.0
#          inet6 addr: fe80::21e:37ff:fe21:38f8/64 Scope:Link
#          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
#          RX packets:223 errors:0 dropped:0 overruns:0 frame:0
#          TX packets:208 errors:0 dropped:0 overruns:0 carrier:0
#          collisions:0 txqueuelen:100
#          RX bytes:126331 (123.3 Kb)  TX bytes:22788 (22.2 Kb)
#          Base address:0x3000 Memory:ee000000-ee020000

   # return a list of tokens
   # tokens separated by ?, list separated by %
   # return number of interfaces found
   q=`$IFCONFIG | $AWK '  BEGIN { numberOfNics=0; result=""; }
         /^(en|wl|eth|ath|wlan|ra).*:Ethernet/ { name = $1;
            mac = $5
            numberOfNics++;
            getline;
   # line with IPV4 infos?
            if ($1 == "inet") {
               match($2,"[0-9]+.[0-9]+.[0-9]+.[0-9]+")
               ip=substr($2,RSTART,RLENGTH);
               match($3,"[0-9]+.[0-9]+.[0-9]+.[0-9]+")
               bc=substr($3,RSTART,RLENGTH);
               match($4,"[0-9]+.[0-9]+.[0-9]+.[0-9]+")
               nm=substr($4,RSTART,RLENGTH);
               getline;
            }
   # line with IPV6 infos? 
			ip6=""	
            if (match($0,"inet6")) {      # skip inet6 address
               match($3,".*/")
               ip6=substr($3,RSTART,RLENGTH-1);
            }
            getline;
            match($2,"[0-9]+")
            rcv=substr($2,RSTART,RLENGTH);
            rcv_error=0
            if (rcv > 0) {
               match($3,"[0-9]+")
               rcv_err=substr($3,RSTART,RLENGTH);
               perc=rcv_err/rcv*100;
               rcv_error = perc
            }
            match($4,"[0-9]+")
            rcv_dropped=substr($4,RSTART,RLENGTH);

            getline;
            match($2,"[0-9]+")
            xmt=substr($2,RSTART,RLENGTH);
            xmt_error=0
            if (xmt > 0) {
               match($3,"[0-9]+")
               xmt_err=substr($3,RSTART,RLENGTH);
               perc=xmt_err/xmt*100;
               xmt_error=perc
            }
            match($4,"[0-9]+")
            xmt_dropped=substr($4,RSTART,RLENGTH);

            if ( result != "" ) {
               result=result "%"
            }
            result=result name "?" mac "?" ip "?" ip6 "?" rcv_error "?" xmt_error "?" rcv_dropped "?" xmt_dropped
            name=""
            mac=""
            ip=""
            rcv_error=""
            xmt_error=""
            }
         END {    print result
            exit numberOfNics
             }
         '`
   INTERFACE_WRD_NO=$?
   INTERFACE_NO=$INTERFACE_WRD_NO

   IFS_OLD=$IFS
   IFS="%"
   i=0
   for interface in $q; do
      let i=i+1
      INTERFACE_TYPE[$i]=$CONNECTION_WRD
      IFS="?"
      j=0
      for element in $interface; do
         case $j in
            0) INTERFACE_NAME[$i]=$element
               debug "Interface $element detected";;
            1) INTERFACE_MAC[$i]=$element
               debug "Interface ${INTERFACE_NAME[$i]}: Mac $element detected";;
            2) INTERFACE_IP[$i]=$element
               debug "Interface ${INTERFACE_NAME[$i]}: IP $element detected";;
            3) INTERFACE_IP6[$i]=$element
               debug "Interface ${INTERFACE_NAME[$i]}: IP6 $element detected";;
            4) INTERFACE_RCV_ERROR[$i]=$element
               debug "Interface ${INTERFACE_NAME[$i]}: RCV $element detected";;
            5) INTERFACE_XMT_ERROR[$i]=$element
               debug "Interface ${INTERFACE_NAME[$i]}: XMT $element detected";;
            6) INTERFACE_RCV_DROPPED[$i]=$element
               debug "Interface ${INTERFACE_NAME[$i]}: RCV-dropped $element detected";;
            7) INTERFACE_XMT_DROPPED[$i]=$element
               debug "Interface ${INTERFACE_NAME[$i]}: XMT-dropped $element detected";;
            *) writeToElizaOnly $MSG_INTERNAL_ERROR;;
         esac
         let j=j+1
      done
   done
   IFS=$IFS_OLD

# eth0      no wireless extensions.

#wlan0     unassociated  ESSID:off/any
#          Mode:Managed  Frequency=nan kHz  Access Point: Not-Associated
#          Bit Rate:0 kb/s   Tx-Power:16 dBm
#          Retry limit:15   RTS thr:off   Fragment thr:off
#          Encryption key:off
#          Power Management:off
#          Link Quality:0  Signal level:0  Noise level:0
#          Rx invalid nwid:0  Rx invalid crypt:0  Rx invalid frag:0
#          Tx excessive retries:0  Invalid misc:220   Missed beacon:0

#wlan0     IEEE 802.11g  ESSID:"ESSID"
#          Mode:Managed  Frequency:2.462 GHz  Access Point: 00:14:6C:E5:F7:1F
#          Bit Rate:36 Mb/s   Tx-Power:15 dBm
#          Retry limit:15   RTS thr:off   Fragment thr:off
#          Encryption key:AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH   Security mode:open
#          Power Management:off
#          Link Quality=67/100  Signal level=-71 dBm  Noise level=-72 dBm
#          Rx invalid nwid:0  Rx invalid crypt:1  Rx invalid frag:0
#          Tx excessive retries:0  Invalid misc:240   Missed beacon:0

   q=`$IWCONFIG 2>&1 | $AWK ' BEGIN { numberOfNics=0; essid=""; result=""; }
         /^(en|wl|eth|ath|wlan|ra).*no wireless/ { next; }          # skip
         /^(en|wl|eth|ath|wlan|ra).*/ {
            numberOfNics++;
            name=substr($1,1,8)   # iwconfig allows IO names > 8 chars, ifconfig allows 8 chars only
            sub("ESSID:","",$4)
                 if ( $4 == "off/any") {
                     essid=""
            }
                 else {
                  gsub("\"","",$4)
               essid=$4
                 }
            getline
            sub("Mode:","",$1)
            mode=$1
            if ( $6 == "Not-Associated" || $6 == "None" ) {
               ap=""
            }
            else {
               ap=$6
            }
            getline
            getline
            getline
            sub("key:","",$2)
            if ( $2 == "off") {
               key=""
            }
            else {
               key=$2
            }

            if ( result != "" ) {
               result=result "%"
            }
            result=result name "?" essid "?" mode "?" ap "?" key
            }
         END {    print result
            exit numberOfNics
             }
         '`

   INTERFACE_WRL_NO=$?
   debug "Number of WLAN nics detected: $INTERFACE_WRL_NO"
   debug "iwconfig scan contents: $q"

   IFS_OLD=$IFS
   IFS="%"
   i=0
   for interface in $q; do
      let i=i+1
      IFS="?"
      j=0
      for element in $interface; do
         case $j in
            0) INTERFACE_WRL_NAME=$element;
               debug "Interface $element detected"
               k=1;
               index=0
               while [[ $k -le $INTERFACE_WRD_NO ]]; do
               if [[ ${INTERFACE_NAME[$k]} == $INTERFACE_WRL_NAME ]]; then
                  debug "Found match for $element"
                  index=$k
               fi
               let k=k+1
               done
               if [[ $index -le 0 ]]; then          # HACK: no match to ifconfig
               let INTERFACE_NO=$INTERFACE_NO+1
               index=$INTERFACE_NO
                  INTERFACE_NAME[$index]=$INTERFACE_WRL_NAME
                  INTERFACE_TYPE[$index]=$CONNECTION_WRL
               debug "Added unmatched -$element-"
               else
                  INTERFACE_TYPE[$index]=$CONNECTION_WRL
               debug "Added matched -$element-"
               fi
               ;;
            1) INTERFACE_ESSID[$index]=$element
               ;;
            2) INTERFACE_MODE[$index]=$element
               ;;
            3) INTERFACE_AP[$index]=$element
               ;;
            4) INTERFACE_KEY[$index]=$element
               ;;
            *) writeToElizaOnly $MSG_INTERNAL_ERROR
               ;;
         esac
         let j=$j+1
      done
   done

   IFS=$IFS_OLD

# log IF states
   local i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      echo "IF:${INTERFACE_NAME[$i]}  IM:${INTERFACE_TYPE[$i]}" >> $STATE
      let i=i+1
   done

   state "DI:$INTERFACE_NO"
   debug "<<detectInterfaces $INTERFACE_NO"

return

}

#################################################################################
#
# --- Check whether there is a eth/ath/wlan/ra network interface for the connection type available.
# --- If yes,execute various tests on the interface
#
# --- Returns 2 if no IP was found
# --- Returns 1 if no network interface was found
# --- Returns 0 otherwise
#
#################################################################################

function checkNetworkInterfaces () {

   debug ">>checkNetworkInterfaces"

   local q
   local i
   local rc=1   # no IF found
   local rcSub

   IP_ADDRESS_FOUND=0

   i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]] ||
            [[ $CONNECTION == $CONNECTION_WRD && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRD ]]; then

         checkNetworkInterfaceCommon $i
         rcSub=$?
         state "cNiC:$i:$rcSub"
         if [[ $rcSub == 0 ]]; then    # there is an IP address and interface
            rc=0
         fi
         if [[ $rcSub == 1 ]]; then    # there is no IP address
            rc=2
         fi
      fi
      let i=i+1

   done

   if [[ $i == 1 ]]; then
         writeToEliza $MSG_NO_VALID_NI_FOUND
   fi

   state "NI:$rc"
   debug "<<checkNetworkInterfaces $rc"

return $rc
}

#################################################################################
#
# Do some common checks
#
# return 0 if there is an ip address and return 1 if there is no IP address
#
#################################################################################

function checkNetworkInterfaceCommon () { # intecheckNetworkInterfacesrfaceIndex

   debug ">>checkNetworkInterfaceCommon"

   local index
   local rc=0
   local name
   local nibble

   # check whether there is a ip address on the interface
   # if there is an ip address check whether there are rcv and xmit errors

   index=$1
   name=${INTERFACE_NAME[${index}]}

   if [[ -z ${INTERFACE_IP[${index}]} ]]; then                                 # no ip address
      writeToEliza $MSG_NO_IP_ASSIGNED_TO_NIC $name
      rc=1
   else
      nibble=`echo ${INTERFACE_IP[${index}]} | cut -d "." -f 1`         # check for APIPA address

      debug "--checkForAPIPAdress"

      if [[ $nibble  == 169 ]]; then
         writeToEliza $MSG_APIPA_DETECTED ${INTERFACE_IP[${index}]} $name
      fi

      debug "--checkForRCV-XMTErrors"

      if [[ ${INTERFACE_RCV_ERROR[${index}]} > $MAX_ERROR_PERCENT ]]; then      # receive errors
         writeToEliza $MSG_NIC_ERRORS $name
      else
         if [[ ${INTERFACE_XMT_ERROR[${index}]} > $MAX_ERROR_PERCENT ]]; then   # transmission errors
            writeToEliza $MSG_NIC_ERRORS $name
         fi
      fi

      debug "--checkForRCV-XMTDrops"

      if [[ ${INTERFACE_RCV_DROPPED[${index}]} -gt 0 ]]; then      # receive messages dropped
         writeToEliza $MSG_NIC_DROPPED $name
      else
         if [[ ${INTERFACE_XMT_DROPPED[${index}]} -gt 0 ]]; then   # transmission messages dropped
            writeToEliza $MSG_NIC_DROPPED $name
         fi
      fi

   fi

   state "NIC:$rc"
   debug "<<checkNetworkInterfaceCommon $rc"

return $rc

}

#################################################################################
#
# Do some common tests for wired interfaces
#
# (empty right now)
#
#################################################################################

function checkNetworkInterfaceWrd () {
   debug ">>checkNetworkInterfacesWrd"
   rc=0
   state "NIWD:$rc"
   debug "<<checkNetworkInterfacesWrd $rc"
   return $rc
}

#################################################################################
#
# Do some common tests for wireless interfaces for HW problems
#
# Return 0 if no errors
# Return 1 if there are errors
#
#################################################################################

function checkNetworkInterfaceWrlHW () {
   local rc
   local finalrc=0
   debug ">>checkNetworkInterfacesWrlHW"

   checkForWLANKillSwitch
   rc=$?
   if [[ $rc != 0 ]]; then
      writeToEliza $MSG_WLAN_KILL_SWITCH_ON
      finalrc=1
   fi

   if [[ $finalrc == 0 ]]; then
      checkForNdisWrapperAndLinuxModule
      rc=$?
      if [[ $rc != 0 ]]; then
         finalrc=1
      fi
   fi

   if [[ $finalrc == 0 ]]; then
         checkForMissingWLANFirmware
         rc=$?
         if [[ $rc != 0 ]]; then
            writeToEliza $MSG_POSSIBLE_WLAN_FIRMWARE_PROBLEMS
            finalrc=1
         fi
   else
         writeToEliza $MSG_NO_ANALYSIS_AS_USER "WLAN_firmware_problems"
   fi

   debug "<<checkNetworkInterfacesWrlHW $finalrc"
return $finalrc
}

#################################################################################
#
# Do some common tests for wireless interfaces for auth problems
#
# Return 0 if no errors
# Return 1 if there are errors
#
#################################################################################

function checkNetworkInterfaceWrlAUTH () {
   local rc
   local finalrc=0
   debug ">>checkNetworkInterfacesWrlAUTH"

   # check for mode set
   # if not WEP or WPA key missing

   # check for wpa_supplicant to be active and create a warning message

   o=`ps -eo comm 2>/dev/null | $EGREP wpa_supplicant`
   if [[ -z $o ]]; then
      writeToEliza $MSG_NO_WPA_SUPPLICANT_ACTIVE
      finalrc=1
   fi

   state "NIWLA:$finalrc"
   debug "<<checkNetworkInterfacesWrlAUTH $finalrc"
   return $finalrc
}

#################################################################################
#
# --- Check whether there is at least one networkdevice available. Use lspci
#
# -- Return the number of devices found
#
#################################################################################

function checkForAtLeastOneNic () {

   debug ">>checkForAtLeastOneNic"


   if [[ $CONNECTION == $CONNECTION_WRL ]]; then
         rc=`$PERL -e'
            foreach my $line (qx %'$LSPCI'%) {
               if ($line =~ /network.*controller|ethernet.*controller.*(wireless|802\.11)/i) {
                  print "1";
                  exit;
               }
            }
            foreach my $line (qx %'$LSUSB'%) {
               if ($line =~ /wlan|wireless|802\.11/i) {
                   print "1";
                   exit;
                }
            }
            print "2";
            '`
   else           # wired connection - assumption: no USB card used
         rc=`$PERL -e'
            foreach my $line (qx %'$LSPCI'%) {
               if ($line =~ /ethernet.*controller/i && $line !~ /wireless|802\.11/i) {
                  print "1";
                  exit;
               }
            }
            print "0";
            '`
   fi

   state "FALON:$rc"
   debug "<<checkForAtLeastOneNic $rc"

return $rc

}

#################################################################################
#
# --- Check whether there are multiple nics in the same subnet.
#
# --- Return 0 if no nics are in the same subnet
# --- Return 1 if there are nics in the same subnet
#
#################################################################################

function checkForNicsInSameSubnet() {

   local rc
   local q

   debug ">>checkForNicsInSameSubnet"

   q=`$IFCONFIG  | $PERL -e 'my $nic; my %nicsFound;
#         collect all nics with their ip and netmask
         while (my $line=<STDIN>) {
#            print "$line \n";
            if ( $line=~/^([a-z0-9]+).*/) {
               $nic=$1;
            } else {
#                                $1 (ip)                  $2 (bc)                 $3 (mask)
               $line=~/.*:(\d+\.\d+\.\d+\.\d+).*:(\d+\.\d+\.\d+\.\d+).*:(\d+\.\d+\.\d+\.\d+)/;
               if ( $1 != "") {
                  my @ipNibbles=split /\./, $1, 4;
                  my @maskNibbles=split /\./, $3, 4;
                  $netNibbles[0]=$ipNibbles[0] + 0 & $maskNibbles[0];
                  $netNibbles[1]=$ipNibbles[1] + 0 & $maskNibbles[1];
                  $netNibbles[2]=$ipNibbles[2] + 0 & $maskNibbles[2];
                  $netNibbles[3]=$ipNibbles[3] + 0 & $maskNibbles[3];
                  my $maskedIP="$netNibbles[0]\.$netNibbles[1]\.$netNibbles[2]\.$netNibbles[3]";
                  $nicsFound{$nic} = $maskedIP;
#                  print ".$nic,$maskedIP.";
               }
            }
             }

#         check whether there are identical networks used by the nics
#            $nicsFound{"eth1"} = "192.168.0.0";

         my @ips=values %nicsFound;
         my @nics=keys %nicsFound;
         my $size=$#nics;
         for (my $i=0; $i<$size; $i++) {
            for (my $j=$i+1; $j<=$size; $j++) {
                  if ($ips[$i] eq $ips[$j]) {
                     print "$nics[$i]:$nics[$j]"
                  }
            }
         }
'`
    checkForNicsInSameSubnet_Result=$q

    if [[ $q != "" ]]; then
      rc=1
    else
      rc=0;
    fi

state "NISS:$rc"
debug "<<checkForNicsInSameSubnet $rc"

return $rc

}

#################################################################################
#
# --- Check whether there are no modules loaded or any inactive modules
#
# --- Return 0 if nothing special
# --- Return 1 if there is no module loaded
# --- Return 2 if there are inactive modules
# --- Return 3 if there is no module loaded and inactive modules
#
#################################################################################

function checkModules() {
   debug ">>checkModules"

   local ifce
   local rc
   local result

   if [[ $CONNECTION == $CONNECTION_WRL ]]; then
      ifce=""
   else
      ifce="eth"
   fi

   result=`echo $ifce |  $PERL -e'

my $active=0;
my $inactive=0;
my @inactiveName=();
my $activeName="";
my $nicName="";
my $found=0;

my $nic;
my $nicI=<>;
if ( $nicI =~ /eth/ ) {
   $nic="Ether";
}
else {
   $nic="(Network|WLAN)";
}

foreach my $line (qx %'$HWINFO' --netcard%) {

#  print $line;

   if ($line =~ /^\d+:/ && $found) {
      last;
   }
   if ($line =~ /^\d+:.+$nic/) {
      $found=1;
      next;
   }

   if ($line =~ /Driver Status: (\w+).*(not|in).*active/) {
      $inactive++;
      if (scalar @inactiveName == 0) {
         push @inactiveName,$1;
      }
      else {
         push @inactiveName,",$1";
      }
   }
      elsif ($line =~ /Driver Status: (\w+).*active/) {
      $active++;
      $activeName=$1;
   }
      elsif ($line =~ /Device File: (\w+)$/) {
      $nicName = $1;
   }
}
if ( $found ) {
   print "$nicName | $activeName | @inactiveName\n";
}
if ($activeName eq "" && scalar @inactiveName == 0) {
  exit 3
}
if ($activeName eq "") {
  exit 1
}
if (scalar @inactiveName > 0) {
  exit 2
}
exit 0'`

   rc=$?

   nicName=`echo $result | cut -d "|" -f 1`
   active=`echo $result | cut -d "|" -f 2`
   inactive=`echo $result | cut -d "|" -f 3`

   if [[ $rc  == 1 || $rc == 3 ]]; then
      writeToEliza $MSG_HW_NO_ACTIVE $nicName
   fi
   if [[ $rc  == 2 ]]; then
      writeToEliza $MSG_HW_SOME_INACTIVE $inactive $nicName
   fi
   state "CM:$rc"
   debug "<< checkModules $rc"
return $rc
}

#################################################################################
#
# --- Check MTU
#
#################################################################################

function checkMTU() {

debug ">>checkMTU"

   local DFDetected
   local testMTU
   local dummy
   local rc

#   detect maximum possible MTU for client or router using pppoe

   DFDetected=0
   testMTU=1600

   while [[ $DFDetected == 0 ]]; do
       dummy=`$PING -c1 195.135.220.3 -s $testMTU -M do | $GREP "DF set"`
      DFDetected=$?
      if [[ $DFDetected == 0 ]]; then
         let testMTU=$testMTU-100
      fi
   done

   DFDetected=0
   let testMTU=$testMTU+100

   while [[ $DFDetected == 0 ]]; do
      dummy=`$PING -c1 195.135.220.3 -s $testMTU -M do | $GREP "DF set"`
      DFDetected=$?
      if [[ $DFDetected == 0 ]]; then
         let testMTU=$testMTU-10
      fi
   done

   DFDetected=0
   let testMTU=$testMTU+10

   while [[ $DFDetected == 0 ]]; do
      dummy=`$PING -c1 195.135.220.3 -s $testMTU -M do | $GREP "DF set"`
      DFDetected=$?
      if [[ $DFDetected == 0 ]]; then
         let testMTU=$testMTU-2
      fi
   done

   let mtuRequired=$testMTU+28

#   mtuRequired=`ping -c1 195.135.220.3 -s 1600 -M do | perl -e 'my $mtu; while(<>) { if ($_=~/mtu.* (\d+)\)/) { print "$1"};
#}'`
   defaultGatewayNic=`$ROUTE -n | $AWK '/^[0]+\.[0]+\.[0]+\.[0]+/ { print $NF; } '`
   mtuActive=`$IFCONFIG $defaultGatewayNic | $PERL -e 'my $mtu; while(<>) { if ($_=~/MTU:(\d+)/) { print "$1"}; }'`

   if [[ $mtuRequired -lt $mtuActive ]]; then
      rc=1
   else
      rc=0
   fi
   state "MTU:$rc"
   debug "<<checkMTU $rc $mtuRequired"
   return $rc

}

#################################################################################
#
# --- Check whether there is a default route defined
#
# --- return
# ---    0 if there is no default route set
# ---    1 if there is a default route set
# --- and set global variable checkDefaultRoute_gateway_host to the hostname of the default gateway
# --- and set global variable checkDefaultRoute_gateway_nic to the nic which is used for the default gateway
#
#################################################################################

function checkDefaultRoute () {

   debug ">>checkDefaultRoute"

   local q
   local i
   local v
   local rc

# 0.0.0.0         192.168.0.1     0.0.0.0         UG    0      0        0 eth0

    q=`$ROUTE -n | $AWK '/^[0]+\.[0]+\.[0]+\.[0]+/ { print$0; } '`

    if [[ $q == "" ]]; then
      rc=0
    else
      rc=1
      i=1
      for v in $q; do
         if [[ $i == 2 ]]; then
            checkDefaultRoute_gateway_host=$v
         fi
         if [[ $i == 8 ]]; then
            checkDefaultRoute_gateway_nic=$v
         fi

         let i=i+1
      done;
   fi
   state "DR:$rc"
   debug "<<checkDefaultRoute $rc"
   CHECK_DEFAULT_ROUTE=$rc
return $rc

}

#################################################################################
#
# --- Cat all config files in /etc/sysconfig/network/ifcfg-*
# --- Masquerade wireless keys and passwords
#
#################################################################################

function catMyConfig() {
local C

# masquerade WLAN credentials

# BOOTPROTO='dhcp'
# BROADCAST=''
# ETHTOOL_OPTIONS=''
# IFPLUGD_PRIORITY='10'
# IPADDR=''
# MTU=''
# NAME='Intel Thinkpad  X60s, R60e model 0657'
# NETMASK=''
# NETWORK=''
# REMOTE_IPADDR=''
# STARTMODE='ifplugd'
# USERCONTROL='no'
# WIRELESS_AP=''
# WIRELESS_AUTH_MODE='open'
# WIRELESS_BITRATE='auto'
# WIRELESS_CA_CERT=''
# WIRELESS_CHANNEL=''
# WIRELESS_CLIENT_CERT=''
# WIRELESS_CLIENT_KEY=''
# WIRELESS_CLIENT_KEY_PASSWORD=''
# WIRELESS_DEFAULT_KEY='0'
# WIRELESS_EAP_AUTH=''
# WIRELESS_EAP_MODE=''
# WIRELESS_ESSID='FRAMP'
# WIRELESS_FREQUENCY=''
# WIRELESS_KEY=''
# WIRELESS_KEY_0=''
# WIRELESS_KEY_1=''
# WIRELESS_KEY_2=''
# WIRELESS_KEY_3=''
# WIRELESS_KEY_LENGTH='128'
# WIRELESS_MODE='Managed'
# WIRELESS_NICK=''
# WIRELESS_NWID=''
# WIRELESS_PEAP_VERSION=''
# WIRELESS_POWER='yes'
# WIRELESS_WPA_ANONID=''
# WIRELESS_WPA_IDENTITY=''
# WIRELESS_WPA_PASSWORD=''
# WIRELESS_WPA_PSK=''

if (( ! $CONFIG_READABLE )); then
	writeToEliza $MSG_NO_ANALYSIS_AS_USER "network_config_files"
	return 0
fi

for C in `ls /etc/sysconfig/network/ifcfg-[earwd]* 2>/dev/null`; do
   c="cat $C"
   m=`colorate "$c"`
   echo $m >> $LOG;
   cat $C | $GREP -v "^#" | $GREP -v "^$" \
   | $AWK "BEGIN { FS=\"=\"} \
      /WIRELESS_KEY[ ]*=|WIRELESS_KEY_[0-9][ ]*=|WIRELESS_DEFAULT_KEY[ ]*|WIRELESS_KEY_LENGTH[ ]*=|\
      WIRELESS_WPA_IDENTITY[ ]*=|WIRELESS_WPA_PASSWORD[ ]*=|WIRELESS_WPA_PSK[ ]*=/ \
      { cred=\"@@@@@@\"; \
        if ( \$2 ~ /['\"].+['\"]/ || \$2 !~ /['\"]/ ) { \
           if ( substr(\$2,1,1) ~ /['\"]/ ) {
              cred=substr(\$2,1,1) cred substr(\$2,1,1);
         }
           print \$1 \"=\" cred; next;
         }
      }
      { print \$0}" | $EGREP -v ".*=''" >> $LOG
done
return 0
}

#################################################################################
#
# --- Check whether ipv6 module is loaded
#
# --- return 1 if module is loaded
# --- return 0 otherwise
#
#################################################################################

function checkForIPV6() {

   debug ">>checkForIPV6"

   local l

   rc=0
   i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]] ||
          [[ $CONNECTION == $CONNECTION_WRD && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRD ]]; then
         if [[ -n ${INTERFACE_IP6[$i]} ]]; then
            rc=1
            break
         fi
      fi
      ((i++))
   done

   state "IP6:$rc"
   debug "<<checkForIPV6 $rc"

   return $rc

}

function checkForSSID () {
   local rc
   local i
   debug ">>checkForSSID"
   rc=0

   i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]]; then
         wlanif=${INTERFACE_NAME[$i]}
         debug "checking WLAN $wlanif"
         rc=`$IWLIST $wlanif scanning 2>/dev/null | $GREP -c \"$essid\"`
         if [[ $rc == 0 ]]; then
            writeToEliza $MSG_WLAN_NO_SSID_IN_SCAN_FOUND $wlanif
            rc=1
         fi
      fi
      let i=$i+1
   done
   debug "<<checkForSSID $rc"
return $rc
}

#wlan0     Scan completed :
#          Cell 01 - Address: 00:14:6C:E5:F7:1F
#                    ESSID:"FRAMP"
#                    Protocol:IEEE 802.11bg
#                    Mode:Master
#                    Channel:11
#                    Frequency:2.462 GHz (Channel 11)
#                    Encryption key:on
#                    Bit Rates:1 Mb/s; 2 Mb/s; 5.5 Mb/s; 6 Mb/s; 9 Mb/s
#                              11 Mb/s; 12 Mb/s; 18 Mb/s; 24 Mb/s; 36 Mb/s
#                              48 Mb/s; 54 Mb/s
#                    Quality=59/100  Signal level=-72 dBm  Noise level=-72 dBm
#                    IE: WPA Version 1
#                        Group Cipher : TKIP
#                        Pairwise Ciphers (2) : CCMP TKIP
#                        Authentication Suites (1) : PSK
#                    IE: IEEE 802.11i/WPA2 Version 1
#                        Group Cipher : TKIP
#                        Pairwise Ciphers (2) : CCMP TKIP
#                        Authentication Suites (1) : PSK
#                    Extra: Last beacon: 708ms ago
#

function detectAPs () {
   local wlanif
   local i
   local num=0

   debug ">>detectAPs $INTERFACE_NO"

   i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]]; then
         wlanif=${INTERFACE_NAME[$i]}
         $IWLIST $wlanif scanning 2>/dev/null | $EGREP -i "ESSID|Channel|Quality|Signal" >> $LOG      # skip IE: Unknown
         if [[ $? == 0 ]]; then
            let num=$num+1
         fi
      fi
      let i=$i+1
   done

   if [[ $num == 0 ]]; then
      echo "No WLANs found" >> $LOG
   fi

   state "AP:$num"
   debug "<<detectAPs"

}

#################################################################################
#
# --- Do common tests if a wireless interface has no IP address
#
#################################################################################

function checkNetworkInterfaceWrlNoIP () {
   local rc
   local q
   local finalRC=0
   local i
   local wlanif

   debug "<<checkNetworkInterfaceWrlNoIP"

   checkForSSID

   i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]]; then
         wlanif=${INTERFACE_NAME[$i]}

         $IWLIST $wlanif scanning 2>/dev/null 2>/dev/null | $GREP "ESSID" 1>/dev/null
         if [[ $? != 0 ]]; then
            writeToEliza $MSG_WLAN_NO_SCAN $wlanif
            debug "HW/Driver problems on WLAN"
            finalRC=1

# no connection to AP

#wlan0     unassociated  ESSID:off/any
#          Mode:Managed  Frequency=nan kHz  Access Point: Not-Associated
#          Bit Rate:0 kb/s   Tx-Power:16 dBm
#          Retry limit:15   RTS thr:off   Fragment thr:off
#          Encryption key:off
#          Power Management:off
#          Link Quality:0  Signal level:0  Noise level:0
#          Rx invalid nwid:0  Rx invalid crypt:0  Rx invalid frag:0
#          Tx excessive retries:0  Invalid misc:15   Missed beacon:0

      elif [[ ${INTERFACE_AP[$i]} == "" && ${INTERFACE_ESSID[$i]} == "" ]]; then
         writeToEliza $MSG_WLAN_AUTH_PROBS $wlanif
         debug "Authentication problem on WLAN"
         finalRC=2

#wlan0     unassociated  ESSID:"FRAMP"
#          Mode:Managed  Frequency=nan kHz  Access Point: Not-Associated
#          Bit Rate:0 kb/s   Tx-Power:16 dBm
#          Retry limit:15   RTS thr:off   Fragment thr:off
#          Encryption key:off
#          Power Management:off
#          Link Quality:0  Signal level:0  Noise level:0
#          Rx invalid nwid:0  Rx invalid crypt:0  Rx invalid frag:0
#          Tx excessive retries:0  Invalid misc:18   Missed beacon:0

#         elif [[ ${INTERFACE_AP[$i]} == "" && ${INTERFACE_ESSID[$i]} != "" ]]; then
#         writeToEliza $MSG_WLAN_CON_NOESSID $wlanif
#         debug ""
#         finalRC=3
#     fi

# connection successfully

#wlan0     IEEE 802.11g  ESSID:"FRAMP"
#          Mode:Managed  Frequency:2.462 GHz  Access Point: 00:14:6C:E5:F7:1F
#          Bit Rate:36 Mb/s   Tx-Power:15 dBm
#          Retry limit:15   RTS thr:off   Fragment thr:off
#          Encryption key:xxxx-xxxx-xxxx-xxxx-xxxx-xxxx-xxxx-xxxx   Security mode:open
#          Power Management:off
#          Link Quality=65/100  Signal level=-68 dBm  Noise level=-69 dBm
#          Rx invalid nwid:0  Rx invalid crypt:0  Rx invalid frag:0
#          Tx excessive retries:0  Invalid misc:25   Missed beacon:0

      elif [[ ${INTERFACE_AP[$i]} != "" && ${INTERFACE_ESSID[$i]} != "" ]]; then
         debug "Connection and ESSID"
         finalRC=0
      fi
   fi

   let i=$i+1
   done

   state "NIW:$wlanif-$finalRC"

   debug ">>checkNetworkInterfaceWrlNoIP $finalRC"

   return $finalRC

}

#################################################################################
#
# --- check if networkmanager is enabled and there exist configurations for wireless/wired which will be used by ifup
#
# --- return 1 if there is a configuration mismatch
# --- return 0 otherwise
# --- place in KNETWORK_IF the names of the interfaces which is misconfigured
#
#################################################################################

function checkKnetworkManager () {

debug ">>checkKnetworkManager"

   local f
   local C
   local rc
   local error=0
   local mask
   local nmRunning=0
   KNETWORK_IF=""

   if (( ! $CONFIG_READABLE )); then
   		writeToEliza $MSG_NO_ANALYSIS_AS_USER "static_network_configuration_with_networkmanager"
		return
	fi

	C=`$EGREP -i 'NETWORKMANAGER.*=.*yes' /etc/sysconfig/network/config `
	rc=$?
	
	debug "NM in config enabled: $rc"
	
	if [[ $rc != 0 ]]; then			# not enabled in config
		C=`ps -ef | grep "/sbin/NetworkManager" | grep -v "grep" 2>&1 1>/dev/null`
		if [[ $C != "" ]]; then				# NM active
			debug "Found running NM"
			nmRunning=1
			rc=0
		fi
	fi
	
	debug "NM configured: $rc"
	
	mask="[arwe]"                                                                   # yes
	if [[ $rc == 0 ]]; then                                                         # networkmanager enabled
		if (( ! $nmRunning )); then
			debug "NM not running"
			for f in `ls /etc/sysconfig/network/ifcfg-${mask}* 2>/dev/null`; do      # no configs allowed
				error=1
				if  [[ $KNETWORK_IF == "" ]]; then
					KNETWORK_IF="${f##*-}"
				else
					KNETWORK_IF="${f##*-},$KNETWORK_IF"
				fi
			done
		fi
	else
		debug "NM not running"
		nodhcp=0	# NM not configured or running, check whether dhcp is used in config for all IFs 
		for f in `ls /etc/sysconfig/network/ifcfg-${mask}* 2>/dev/null`; do      # process all configs
			if $GREP -i "BOOTPROTO=.*dhcp" $f 1>/dev/null 2>/dev/null; then
				debug "$f OK"
				:
			else
				debug "$f NOK"
				nodhcp=1
				break
			fi
		done
		if (( $nodhcp )); then
			writeToEliza $MSG_IFUP_CONFIGURED                                                         # warning that ifup is enabled
		fi
	fi

   state "KM:$error $nodhcp"
   debug "<<checkKnetworkManager $error $KNETWORK_IF"

   return $error

}

#################################################################################
#
# --- check for missing firmware for WLAN cards
#
# --- return 1 if string found
#
#################################################################################

function checkForMissingWLANFirmware() {

   debug ">>checkForMissingWLANFirmware"
   local rc
   local testString
   testString="((microcode|firmware).*(fail|error|not.*found))|prism.*faulty|((fail|error).*(microcode|firmware))"
#   $TAIL -n $NUMBER_OF_LINES_TO_CHECK_IN_VAR_LOG_MESSAGES ${VAR_LOG_MESSAGE_FILE}* | $EGREP -i $testString > /dev/null
#     rc=$?
#
#   if [[ $rc == 0 ]]; then
#      rc=1
#   else
      dmesg | $EGREP -i $testString > /dev/null
      if [[ $rc == 0 ]]; then
         rc=1
      else
        rc=0
      fi
#   fi

   debug ">>checkForMissingWLANFirmware $rc"

   return $rc

}

#################################################################################
#
# --- check if the WLAN kill switch is on
#
# --- return 1 is yes
# --- return 0 otherwise
#
#################################################################################


function checkForWLANKillSwitch() {

   debug ">>checkForWLANKillSwitch"
   local rc
   local rfkillResult
   local dummy
   local temprc

# try rfkill first if its available

#	TODO !!! Use vars for commands initialized below
   if `isCommandAvailable rfkill`; then
	rfkillResult=`$RFKILL list wifi`
	debug "rfKillResult: $rfkillResult"
	if [[ $rfkillResult != "" ]]; then
		debug "rfkill tried"
	#0: phy0: Wireless LAN
	#	Soft blocked: no
	#	Hard blocked: yes
		`echo $rfkillResult | $GREP "blocked.*yes" >/dev/null`
		if [ $? == 0 ]; then
			rc=1
			debug "<<checkForWLANKillSwitch1 $rc"
			return $rc
		fi
	fi
   fi

# now check for messages in dmesg

   `dmesg | $EGREP -i "radio.*disabled|disabled.*radio|radio.*switch.*off|off.*radio.*switch" > /dev/null`
   temprc=$?

   if [[ $temprc == 0 ]]; then
      rc=1
	debug "dmesg used"
   else
	rc=0

# still no success, use hwinfo if available

#28: PCI 400.0: 0282 WLAN controller
#  Model: "Intel ThinkPad R60e/X60s"
#  Vendor: pci 0x8086 "Intel Corporation"
#  Device: pci 0x4227 "PRO/Wireless 3945ABG [Golan] Network Connection"
#  SubVendor: pci 0x8086 "Intel Corporation"
#  SubDevice: pci 0x1011 "ThinkPad R60e/X60s"
#  Driver: "iwl3945"
#  Driver Modules: "iwl3945"
#  Device File: wlan0      <=== missing Link detected msg
#    Driver Status: iwl3945 is active
#    Driver Activation Cmd: "modprobe iwl3945"
#29: PCI 600.0: 0200 Ethernet controller
#  Model: "Broadcom NetLink BCM5906M Fast Ethernet PCI Express"
#  Vendor: pci 0x14e4 "Broadcom"
#  Device: pci 0x1713 "NetLink BCM5906M Fast Ethernet PCI Express"
#  SubVendor: pci 0x17aa "Lenovo"
#  SubDevice: pci 0x3861
#  Driver: "tg3"
#  Driver Modules: "tg3"
#  Device File: eth0
#  Link detected: no
#    Driver Status: tg3 is active
#    Driver Activation Cmd: "modprobe tg3"

#   if `isCommandAvailable hwinfo`; then

#	debug "hwinfo used"
#	debug "hwinfo: $HWINFO"

#      if [[ $CONNECTION == $CONNECTION_WRD ]]; then
#         CONN="eth"
#         PARM="--netcard"
#      else
#         CONN="eth|ath|wlan|ra"
#         PARM="--wlan"
#      fi
#
#      devs=`$PERL -e '
#       my $line;
#       my $multiple=0;
#       my $devices="";
#       my $linkDetected="";
#       my $isActive="";
#
#       sub chk {
#                  if ($isActive eq "yes" && $linkDetected ne "yes") {
#                     if ($devices != "") {
#                        $devices="$devices,$device";
#                     }
#                     else {
#                        $devices="$device";
#                     }
#                  }
#        }
#
#       foreach $line (qx %'$HWINFO' '$PARM'%) {
#            if ($line =~ /Device File.*: ([a-z0-9]+)/) {
#                if ($device ne "" && $device =~ '$CONN') {
#                        chk();
#                }
#                else {
#                       $device=$1;
#                       $linkDetected="";
#                       $isActive="";
#                }
#            }
#            if ($line =~ /Link detected: ([a-zA-z]+)/) {
#               $linkDetected=$1;
#            }
#            if ($line =~ /Driver Status:.+is active/) {
#               $isActive="yes";
#            }
#         }
#        chk();
#        print $devices'`
#
#      if [[ $devs != "" ]]; then
#         rc=1
#      else
#         rc=0
#      fi
#
#      fi # hwinfo available

   fi # check hwinfo instead of dmesg

   debug "<<checkForWLANKillSwitch $rc"

   return $rc
}

##################################################################################
#
#  --- Ask user for environment
#
##################################################################################

# --- Ask for the NW topology used

function getTopology () {
   local answer
   local answerNo
   local answerOffset
   TOPOLOGY=0
   TOPOLOGY_DM_LC=1
   TOPOLOGY_DR_LC=2
   TOPOLOGY_DM_LR_LC=3
   TOPOLOGY_DR_LR_LC=4
   TOPOLOGY_AP_LC=5
   TOPOLOGY_WR_LC=6
   TOPOLOGY_AP_LR_LC=7
   TOPOLOGY_WR_LR_LC=8

   if [[ $TOPOLOGYTYPEOPTION -eq 0 ]]; then

      writeToConsole $MSG_EMPTY_LINE
      writeToConsole $MSG_GET_TOPOLOGY

      while [[ $TOPOLOGY == 0 ]]; do
         if [[ $CONNECTION == $CONNECTION_WRD ]]; then
            writeToConsole $MSG_TOPO_DM_LC
            writeToConsole $MSG_TOPO_DR_LC
            writeToConsole $MSG_TOPO_DM_LR_LC
            writeToConsole $MSG_TOPO_DR_LR_LC
            answerNo=4
            answerOffset=0
         else
            writeToConsole $MSG_TOPO_AP_LC
            writeToConsole $MSG_TOPO_WR_LC
            writeToConsole $MSG_TOPO_AP_LR_LC
            writeToConsole $MSG_TOPO_WR_LR_LC
            answerNo=4
            answerOffset=4
         fi

         writeToConsoleNoNL $MSG_PLEASE_CORRECT_ANSWER $answerNo
         read answer
         if [[ "$answer" -le 0 || "$answer" -gt $answerNo ]]; then
            writeToConsole $MSG_UNSUPPORTED_TOPOLOGY
            answer=-1
         else
            let TOPOLOGY=answer+answerOffset
            answer=0
         fi
      done
   else
      TOPOLOGY=$TOPOLOGYTYPEOPTION
   fi

#   if [[ $TOPOLOGYTYPEOPTION -ne 0 ]]; then

      writeToElizaOnly $MSG_EMPTY_LINE
      writeToElizaOnly $MSG_GET_TOPOLOGY
      case $TOPOLOGY in
         1) writeToElizaOnly $MSG_TOPO_DM_LC;;
         2) writeToElizaOnly $MSG_TOPO_DR_LC;;
         3) writeToElizaOnly $MSG_TOPO_DM_LR_LC;;
         4) writeToElizaOnly $MSG_TOPO_DR_LC;;

         5) writeToElizaOnly $MSG_TOPO_AP_LC;;
         6) writeToElizaOnly $MSG_TOPO_WR_LC;;
         7) writeToElizaOnly $MSG_TOPO_AP_LR_LC;;
         8) writeToElizaOnly $MSG_TOPO_WR_LR_LC;;

         *) writeToElizaOnly $MSG_INTERNAL_ERROR;;
      esac
#   fi
}

# --- Ask for the NW connection used

function getConnection () {
   local answer
   CONNECTION=0
   CONNECTION_WRD=2
   CONNECTION_WRL=1

   if [[ $CONNECTIONTYPEOPTION -eq 0 ]]; then

#      writeToConsole $MSG_EMPTY_LINE
      writeToConsole $MSG_GET_CONNECTION

      while [[ $CONNECTION == 0 ]]; do
         writeToConsole $MSG_CON_WRL
         writeToConsole $MSG_CON_WRD
         writeToConsoleNoNL $MSG_PLEASE_CORRECT_ANSWER 2
         read answer
         if [[ "$answer" -le 0 || "$answer" -gt 2 ]]; then
            writeToConsole $MSG_UNSUPPORTED_CONNECTION
            answer=-1
         else
            CONNECTION=$answer
            answer=0
         fi
      done
   else
      CONNECTION=$CONNECTIONTYPEOPTION
   fi

   if [[ $CONNECTION -eq 1 ]]; then
	   FLAGS="${FLAGS}w"   # turn on wireless outputs
   fi

#   if [[ $CONNECTIONTYPEOPTION -ne 0 ]]; then
      writeToElizaOnly $MSG_EMPTY_LINE
      writeToElizaOnly $MSG_GET_CONNECTION
      case $CONNECTION in
         1) writeToElizaOnly $MSG_CON_WRL
            ;;
         2) writeToElizaOnly $MSG_CON_WRD
            ;;
         *) writeToElizaOnly $MSG_INTERNAL_ERROR
            ;;
      esac
#   fi
}


# --- Ask for the host the script was run on

function getExecutionHost () {
   
   if [[ $EXECUTIONHOSTOPTION -eq 0 ]]; then

      EXECUTION_HOST_CL=1
      EXECUTION_HOST_RT=2
      EXECUTION_HOST=0

      if [[ $TOPOLOGY != $TOPOLOGY_DM_LC && $TOPOLOGY != $TOPOLOGY_DR_LC && $TOPOLOGY != $TOPOLOGY_AP_LC && $TOPOLOGY != $TOPOLOGY_WR_LC ]]; then
         writeToConsole $MSG_EMPTY_LINE
         writeToConsole $MSG_GET_HOST

         while [[ $EXECUTION_HOST == 0 ]]; do
            writeToConsole $MSG_HOST_CL
            writeToConsole $MSG_HOST_RT
            writeToConsoleNoNL $MSG_PLEASE_CORRECT_ANSWER 2
            read answer
            if [[ "$answer" -le 0 || "$answer" -gt 2 ]]; then
               writeToConsole $MSG_UNSUPPORTED_HOST
            else
               EXECUTION_HOST=$answer
            fi
         done
      else
         EXECUTION_HOST=$EXECUTION_HOST_CL   # has to be the client
      fi
   else
      EXECUTION_HOST=$EXECUTIONHOSTOPTION
   fi

#  if [[ $EXECUTIONHOSTOPTION -ne 0 ]]; then

      writeToElizaOnly $MSG_EMPTY_LINE
      writeToElizaOnly $MSG_GET_HOST
      case $EXECUTION_HOST in
         1) writeToElizaOnly $MSG_HOST_CL
            ;;
         2) writeToElizaOnly $MSG_HOST_RT
            ;;
         *) writeToElizaOnly $MSG_INTERNAL_ERROR
            ;;
      esac
#   fi

}

# --- Ask for the ESSID if WLAN check

function getESSID () {

   essid=""
   local answer
   local chars
   local i

   if [[ $CONNECTION == $CONNECTION_WRL ]]; then
      if [[ $ESSIDOPTION == "" ]]; then
          while [[ $essid == "" ]]; do

         writeToConsole $MSG_EMPTY_LINE
         writeToConsoleNoNL $MSG_GET_ESSID

         read answer
         essid=$answer

         chars=${#answer}
         echo -n $'\x1b[1A\x1b[2K'      # masquerade SSID - just in case
         writeToConsoleNoNL $MSG_GET_ESSID
         for ((i=1; $i<=$chars; i++)); do
            echo -n "*"
         done
         echo
      done
   else
      essid=$ESSIDOPTION
   fi

    # masquerade essid

   writeToElizaOnly $MSG_GOT_ESSID $essid    # masqueraded later
   fi

}

##################################################################################
#
# --- check if WLAN should be tested but a wired connection exists
#
# --- return 1 if yes
# --- return 0 otherwise
#
##################################################################################

function checkIfWLANTestButWiredOnline () {

   local i
   local rc=0
   local defaultGatewayNic
   local foundWRLIP=0

   debug ">>checkIfWLANTestButWiredOnline"

   i=1
   while [[ $i -le $INTERFACE_NO ]]; do

#      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL && ${INTERFACE_IP[$i]} != "" ]]; then
#        foundWRLIP=1
#      fi

      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRD && ${INTERFACE_IP[$i]} != "" ]]; then
         defaultGatewayNic=`$ROUTE -n | $AWK '/^[0]+\.[0]+\.[0]+\.[0]+/ { print $NF; } '`
         if [[ $defaultGatewayNic == ${INTERFACE_NAME[$i]} ]]; then   # default GW is wired nic
            rc=1
            checkIfWLANTestButWiredOnline=${INTERFACE_NAME[$i]}
            break;
         fi
      fi
      let i=i+1
   done

#if [[ $foundWRLIP == 0 ]]; then        # no WRL IP found, then ignore an existing WRD connection
#  rc=0
#fi

   debug "<<checkIfWLANTestButWiredOnline $rc"
   state "WLW:$checkIfWLANTestButWiredOnline $rc"

return $rc
}

# checks whether a module is loaded
# returns 1 if module is not loaded

#Module                  Size  Used by
#nfs                   227500  1
#lockd                  63864  2 nfs
#nfs_acl                 7552  1 nfs
#sunrpc                160892  4 nfs,lockd,nfs_acl
#iptable_filter          6912  0
#ip_tables              16324  1 iptable_filter
#ip6table_filter         6784  0
#ip6_tables             17476  1 ip6table_filter
#x_tables               18308  2 ip_tables,ip6_tables

function moduleNotLoaded () {   # moduleName
   local q
   local rc

   debug ">>moduleNotLoaded $0"

   q=`$PERL -e 'foreach (qx %'$LSMOD'%) {
         (my $module) = ($_ =~ /^(\w+) /);
         if ( $module eq $ARGV[0]) {
            print "$module\n";
            exit 0;
         }
      }
      exit 1;
      ' $0`

   rc=$?
   debug "<<moduleNotLoaded $rc"

}

# checks whether a nl80211 module is loaded
# returns 1 if module is not loaded

#Module                  Size  Used by
#nfs                   227500  1
#lockd                  63864  2 nfs
#nfs_acl                 7552  1 nfs
#sunrpc                160892  4 nfs,lockd,nfs_acl
#iptable_filter          6912  0
#ip_tables              16324  1 iptable_filter
#ip6table_filter         6784  0
#ip6_tables             17476  1 ip6table_filter
#x_tables               18308  2 ip_tables,ip6_tables

function modulenl80211() {   # moduleName
   local q
   local rc

   debug ">>modulenl80211 $0"

   q=`$PERL -e 'foreach (qx %'$LSMOD'%) {
         (my $module) = ($_ =~ /^(\w+) /);
         if ( $module eq $ARGV[0]) {
            print "$module\n";
            exit 0;
         }
      }
      exit 1;
      ' $0`

   rc=$?
   debug "<<modulenl80211 $rc"

}

function checkSSID() {

   debug ">>checkSSID $essid"

$PERL -e '
	# From IEEE 802.11 7.3.2.1
	# 7.3.2.1 Service Set Identity (SSID) element
	my $s=$ARGV[0];
    # print "ESSID $s\n";
	if (
      	  ($s =~ /[?\"\$\[\\\]\+]/) 	        # invalid all the time 
	     || ($s =~ /^[!#;]/)                # invalid in front
	     || ($s =~ /[\x00-\x1F]/)           # non printable character
	     || ($s =~ /[\x80-\xFF]/)           # extended characters >= 0x80
	   ) {
      	  exit 1;
	        }
	else    {
      	  exit 0;
	        }
	' $essid
   rc=$?
   debug "<<checkSSID $rc"
   return $rc
}

function NWElizaStates () {

   debug ">>NWElizaStates `cat $STATE`"

   if (( NWELIZA_ENABLED )); then

      if [[ -z $1 ]]; then
         cat $STATE | $PERL -e 'while (<>) { s/  / /g; s/\n//; s/: /:/; print "$_ " }; print "\n"'
      else
         echo "NWElizaStates $CVS_VERSION"
      fi
   fi
   debug "<<NWElizaStates `cat $STATE`"

}

##################################################################################
#
# --- Check if networkmanager is not used whether there is a config file
#
##################################################################################

function checkNetworkManagerConfigured () {
   local C
   local i
   local rc
   local knme
   local fileName

   debug ">>checkNMConfigured"

   if (( ! $CONFIG_READABLE )); then
   		writeToEliza $MSG_NO_ANALYSIS_AS_USER "Networkmanager_configuration"
		return 0
   fi

   C=`$EGREP -i 'NETWORKMANAGER.*=.*yes' /etc/sysconfig/network/config `
   knme=$?

   i=1
   while [[ $i -le $INTERFACE_NO ]]; do
      if [[ $CONNECTION == $CONNECTION_WRL && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRL ]] ||
            [[ $CONNECTION == $CONNECTION_WRD && ${INTERFACE_TYPE[$i]} == $CONNECTION_WRD ]]; then

        if [[ ${INTERFACE_IP[$i]} == "" ]]; then                                       # no IP address
            fileName="/etc/sysconfig/network/ifcfg-${INTERFACE_NAME[$i]}";

            if [[ $knme != 0 ]]; then                                                   # networkmanager not enabled
               if [[ ! -e $fileName ]]; then
                  writeToEliza $MSG_NO_NIC_CONFIG_FOUND ${INTERFACE_NAME[$i]}
          fi
            fi
		fi
      fi
      let i=i+1
   done

   debug "<<checkNMConfigured"

}

##################################################################################
#
# --- Generate a simple tabular alphabetically sorted list of available firmware
#
##################################################################################

function listFirmware() {


   dir="/lib/firmware"
   # check for missing firmware of broadcom card (thx larry)
   dummy=`$LSPCI -nn | $GREP "14e4:43"`
   if [[ $? == 0 ]]; then
      dir="/lib/firmware/b43"
   fi
   dummy=`$LSPCI -nn | $EGREP "14e4:4301|14e4:4306"`
#      dummy=`lspci -nn | egrep "10de:00f1|1095:0680"`
   if [[ $? == 0 ]]; then
      dir="/lib/firmware/bc43legacy"
   fi
   if [[ -z $1 ]]; then
	listFirmwareDirectory $dir
    else
	echo "ls $dir/*.{fw,ucode,bin}"
    fi
}

function listFirmwareDirectory () {
   local dummy

   if [[ -d $1 ]]; then

      $PERL -e 'my $i=0;
            my $LIMIT=3;
	    my $dir=$ARGV[0];
	    opendir(DIR, $dir) or die $!;

	    my @files = sort readdir(DIR);
	    while (my $m = shift @files) {
               next unless (-f "$dir/$m");
               next unless ($m =~ m/\.(ucode|fw|bin)$/);

               printf "| %-24s","$m";
               if ( $i++ == $LIMIT ) {
                  print " |\n";
                  $i=0;
               }
            }
            if ( $i != 0 ) {
               print "|\n";
            }' $1 >> $LOG

   else
       echo "$1 not found" >> $LOG
   fi
}

##################################################################################
#
# --- Generate a simple tabular alphabetically sorted list of loaded modules
#
# To reduce the length of the list common non network related modules are filtered
#
##################################################################################

function listLoadedModules () {

   $PERL -e '   my @modules=qx %'$LSMOD' | sort %;
      my $i=0;
      my $modlist1 = qr /acpi|agp|^asus|async|ata_generic|auth_rpcgss|autofs4|battery|bluetooth|bridge|bttv|^bt|button|cdrom|cpu|crc|crypto|crypt|^cx|decoder|dm_mod|dvb|edd|exportfs|ext[34]|^fan$|^fat$|firewire|floppy|fuse/i;
      my $modlist2 = qr /game|ir_common|ide|^ip[6]*table|^ip6|ip[6]*t_|iTCO|joy|lockd|loop|license|Module|matrox|nfs|nf_|nfs|nls|nvidia|parport|pata|pcmcia|pcspkr|pppoe|ppox/i;
      my $modlist3 = qr /processor|psmouse|radeon|raid|reiserfs|^rtc_|^snd|soundcore|sunrpc|thermal|usbcore|usbhid|video|vbox|vesa|vfat|video|vmci|vmmon|vmnet|vsock|x_tables|xor|xt_/i;

      my $COLUMNS = 4;

      foreach my $module (@modules) {
         my ($m, $s, $u, $b) = ($module =~ /(\S+)\s+(\S+)\s+(\S+)(\s+(\S+))?/);
         if ($m =~ $modlist1 || $m =~ $modlist2 || $m =~ $modlist3) {
            next;
         }
         printf "| %-16s","$m";
         if ( $i++ == $COLUMNS ) {
            print " |\n";
            $i=0;
         }
      }
      if ( $i != 0 ) {
            print "|\n";
      }' >> $LOG

}

function checkModulenl80211() {

  debug ">>checkModulenl80211"

      module=`$PERL -e '
   @modules = ("rt2860sta","rt2870sta","rt3070sta","rt3090sta", "rt3562sta", "rt3572sta", "5390sta", "r8192ce_pci", "r8192se_pci", "r8192e_pci", "r8192u_usb", "r8192s_usb", "r8712u");

   $rc="";

   $configFile= "/etc/sysconfig/network/config";
   $releaseFile="/etc/SuSE-release";

   if (-e $releaseFile && qx%egrep -i "VERSION.*=.*11\.3" $releaseFile 2>/dev/null%
      && -e $configFile && qx%egrep -v -i "NETWORKMANAGER.*=.*yes" $configFile 2>/dev/null%) {
      foreach (qx %lsmod%) {
         (my $module) = ($_ =~ /^(\w+) /);
         foreach $m (@modules) {
            if ($m eq $module) {
               $rc=$module;
               last;
            }
         }
      }
   }
   print $rc;
   '`
      if [[ $module != "" ]]; then     # found module
          writeToEliza $MSG_ENL80211L $module
      fi
   debug "<<checkModulenl80211"

}

##################################################################################
#
#  --- checkWLANInterferences
#
# Check whether there are other WLANs which have interferences to the used WLAN channel
#
# Calculate number of APs using the same channel and number of APs interferring with same channel
#
##################################################################################

function checkWLANInterferences () {

   local interferences
   local channels

   debug ">>checkWLANInterferences"

   if [[ $INTERFACE_WRL_NO -gt 0 ]]; then

      IFS='$'		# don't use space as separator, otherwise spaces cause problems when essid is passed into perl code
      channels=`$PERL -e '

      my @channels = (0,0,0,0,0,0,0,0,0,0,0,0,0,0);
      my $essid="'$essid'";
      my $essidChannel=0;
      my $channel;

      foreach my $line (qx %iwlist scan 2>/dev/null%) {
         print $_;
         if ($line =~ /Channel:(\d+)/)  {
               $channels[$1]++;
               $channel=$1;
         }
         if ($line =~ /ESSID:"(.*)"/) {
               if ($essid eq $1) {
                  $essidChannel=$channel;
               }
         }
      }
      $inter=0;
      $min=1;
      $max=$#channels;
      if ($essidChannel-4 > 1) { $min=$essidChannel-4; }
      if ($essidChannel+4 < $#channels) { $max=$essidChannel+4; }

      foreach my $chan ($min .. $max) {
              $inter+=$channels[$chan];
      }

      $inter-=$channels[$essidChannel];
      $sameChannel=$channels[$essidChannel]-1;

      print "$essidChannel $sameChannel";
      exit $inter;
      '`
      unset 
      interferences=$?
      essidChannel=`echo $channels | cut -d " " -f 1`
      sameChannel=`echo $channels | cut -d " " -f 2`

      debug "Interferences: $interferences"
      debug "essidChannel: $essidChannel"
      debug "sameChannel: $sameChannel"

      if [[ $essidChannel -gt 0 ]]; then      # found essid
         if [[ $sameChannel -gt 0 ]]; then
               writeToEliza $MSG_SSID_SAME_CHANNEL $essidChannel $sameChannel
         fi

         if [[ $interferences -gt 0 ]]; then
               writeToEliza $MSG_SSID_INTERFERENCES $essidChannel $interferences
         fi
      fi
    unset IFS
    fi

   debug "<<checkWLANInterferences"

}

##################################################################################
#
#  --- NWEliza
#
##################################################################################

function NWEliza () {
   local result
   local rc
   local ns
   local subRC
   local ip

   askEliza_error=0
   askEliza_warning=0
   askEliza_HW_problem=0

#   detectInterfaces      done already for NWCollect

   checkForAtLeastOneNic
   rc=$?
   if [[ $rc == 0 ]]; then	# wired connection and nothing found with lspci
      writeToEliza $MSG_NO_NIC_FOUND
      return         # without HW there is no network connection possible :-(
   fi

   if [[ $rc == 2 ]]; then	# wireless connection and and nothing found neither with lspci nor lsusb
					# lsusb check is weak so generate warning only
      writeToEliza $MSG_NO_NIC_FOUND_WARNING
   fi

# ---   check for IP address and other possible NI problems
   checkNetworkInterfaces
   rc=$?
   state "cNI:$rc"

   case $rc in

      0) # there is an ip address on the interface
         debug "--NWEliza IP found"

         # ---   Check whether an external ip address can be pinged
         checkIPPings
         rc=$?
	 PING_OK=$rc
         if [[ $rc == 1 ]]; then                                 # ping failure for IP
            checkDefaultRoute
            rc=$?
            if [[ $rc == 0 ]]; then
               writeToEliza $MSG_NO_DEFAULT_GATEWAY_SET
            else
               writeToEliza $MSG_CHECK_DEFAULT_GATEWAY_SETTING $checkDefaultRoute_gateway_host $checkDefaultRoute_gateway_nic
            fi
         else
            checkDNS
            rc=$?
            if [[ $rc -gt 0 ]]; then                         # ping failure for DNS
	       ns=`grep nameserver /etc/resolv.conf`
               subRC=$?
               if [[ $subRC != 0 ]]; then
                  writeToEliza $MSG_NO_NAMESERVER_DEFINED
               else
                  ip=`cat /etc/resolv.conf | awk '/nameserver/ { print $2; exit}'`
                  C=`ping -c 3 -W 3 $ip 2>&1`
                  PING_RES=`echo $C | grep " 0%"`
                  pingRC=$?
                  if [[ $pingRC != 0 ]]; then
                     writeToEliza $MSG_NAMESERVER_NOT_ACCESSIBLE $ip
                  else
                     r=`dig @$ip www.google.com +noques +nostats +time=1 | egrep -v "^;|^$" | egrep "IN.*A"`
                     rc=$?
                     if [[ $rc != 0 ]]; then
                        writeToEliza $MSG_NAMESERVER_NOT_VALID $ip
                     else
                        writeToEliza $MSG_NAMESERVER_PROBLEM_UNKNOWN $ip
                     fi
                  fi
               fi
            fi
         fi

# ---
# --- Misc other general tests if there is an ip address
# ---

         if [[ $DISTRO == $SUSE ]]; then
            checkNetworkManagerConfigured
            checkModulenl80211
         fi

	 if [[ $PING_OK == 0 ]]; then	# MTU check only valid if ping is OK
            checkMTU
            subRC=$?

            if [[ $subRC != 0 ]]; then
               writeToEliza $MSG_POSSIBLE_MTU_PROBLEMS $mtuRequired $defaultGatewayNic $mtuActive
            fi
         fi
     
         checkForNicsInSameSubnet
         rc=$?

         if [[ $rc != 0 ]]; then
            writeToEliza $MSG_DUPLICATE_NETWORKS $checkForNicsInSameSubnet_Result
         fi
         ;;

      1) # no NIC
         debug "--NWEliza no valid NIC found"

         if [[ $CONNECTION == $CONNECTION_WRD ]]; then
            checkNetworkInterfaceWrd
         else
            checkNetworkInterfaceWrlHW
            checkModulenl80211
         fi
         if [[ $DISTRO == $SUSE ]]; then
            checkModules
         fi
         ;;

      2) # no IP found
         # writeToEliza (no IP found) already done before for all NICs
         debug "--NWEliza no IP found"

         if [[ $DISTRO == $SUSE ]]; then
            checkNetworkManagerConfigured
            checkModulenl80211
            fi

         if [[ $CONNECTION == $CONNECTION_WRD ]]; then
            if [[ $DISTRO == $SUSE ]]; then
               checkDHCP     	    
            fi
	    checkNetworkInterfaceWrd
         else
	    checkNetworkInterfaceWrlNoIP
            rc=$?
            if [[ $rc == 0 ]]; then      # essid set and connected
               if [[ $DISTRO == $SUSE ]]; then
                  checkDHCP
               fi
            elif [[ $rc == 1 ]]; then      # HW driver problem
               checkNetworkInterfaceWrlHW
            elif [[ $rc == 2 ]]; then      # auth problem
	       checkNetworkInterfaceWrlAUTH
             fi
#             analyzeSpecificNoWLANNICProblems
         fi
         if [[ $DISTRO == $SUSE ]]; then
	    checkModules
         fi
         ;;

      esac

#  ---
#  --- Tests executed all the time
#  ---

   checkWLANInterferences

   if [[ $CONNECTION == $CONNECTION_WRL ]]; then
   	checkSSID
	rc=$?
	if [[ $rc != 0 ]]; then
      	   writeToEliza $MSG_INVALID_SSID
        fi
   fi

   checkForMissingLink
   rc=$?
   if [[ $rc != 0 ]]; then
      writeToEliza $MSG_MISSING_LINK $checkForMissingLink
   fi

   checkForIPV6
   rc=$?
   if [[ $rc != 0 ]]; then
      writeToEliza $MSG_IPV6_DETECTED
   fi

   if [[ $DISTRO == $SUSE ]]; then
      checkKnetworkManager
      rc=$?
      if [[ $rc != 0 ]]; then
         writeToEliza $MSG_KNETWORKMANAGER_ERROR $KNETWORK_IF
      fi
   fi

   checkIfWLANTestButWiredOnline
   rc=$?
   if [[ $rc != 0 ]]; then
      writeToEliza $MSG_WLAN_WIRED_ONLINE $checkIfWLANTestButWiredOnline
   fi

   debug "<<NWEliza $askEliza_error"
   state "RTDT: $DISTRO_NAME"

  return $askEliza_error
}


##################################################################################
#
# --- check if wpa_supplicant and/or networkmanager process is active
#
##################################################################################

function listActiveProcesses() {
   local rc
   local PROCESSES="wpa_supplicant networkmanager nm-applet"
   local p
   local result=""
   local o

   for p in $PROCESSES; do

      o=`ps -eo comm 2>/dev/null | $EGREP -i $p`
      if [[ -z $o ]]; then
         result="$result $p:NO"
      else
         result="$result $p:YES"
      fi
   done

   echo $result >> $LOG

}

function listWPAProcesses() {
local o

   o=`ps -eo comm 2>/dev/null | $EGREP -i "networkmanager"`      # networkmanager not used
   if [[ -z $o ]]; then

        if [[ -z $1 ]]; then

         o=`ps -eo comm 2>/dev/null | $EGREP -i "wpa_supplicant"`
         if [[ ! -z $o ]]; then
            IFSO=$IFS
            IFS=""
            o=`ps -eo args | $GREP -i [w]pa_supplicant`
            if [[ $o != "" ]]; then
               echo $o >> $LOG
            fi
            IFS=$IFSO
         fi
      else
         o=`ps -eo comm 2>/dev/null | $EGREP -i "wpa_supplicant"`
         if [[ ! -z $o ]]; then
            echo "Active WPA processes"
         fi
      fi
   fi
}

##################################################################################
#
# --- check if ndiswrapper is active and in parallel a Linux driver is loaded
#
# --- return 1 if that's the case, 0 otherwise
#
# --- First suggestion to test this was from IOtz - improved version was suggested from Grothesk
#
##################################################################################

function checkForNdisWrapperAndLinuxModule {

#local linuxNativeDrivers="rt2x00usb rt73usb rt2400pci rt2500pci rt2500usb rt61pci ipw2200 bcm43xx bcm4306 ipw2100 ipw3945 p54pci ath_pci zd1211rw at76c503a rtl8187 r8187"
   local rc
   local q
   local finalrc=0
   local module
   local native

   debug ">>checkForNdisWrapperAndLinuxModule"

   $LSMOD | $GREP -i ndiswrapper > /dev/null
   rc=$?
   if [[ $rc != 0 ]]; then    # ndiswrapper not loaded
      state "NDIS:0"
      debug "<<checkForNdisWrapperAndLinuxModule 0"
      return 0;
   fi

#ts154usb : driver installed
#        device (083A:4501) present (alternate driver: p54usb)

   module=`ndiswrapper -l | $PERL -e '<>=~/(\w+)\s+:/; print "$1";'`                            # get module name used in ndiswrapper

   native=`ndiswrapper -l | $PERL -e 'while (<>) {          # get native driver
        if ($_=~/alternate driver: (\w+)/) {
                print "$1"; leave;
        }
   }'`

# ts154usb : driver installed
# device (083A:4501) present (alternate driver: p54usb)

   ndiswrapper -l  | $GREP -i "alternate driver" > /dev/null
   rc=$?

   if [[ $rc == 0 ]]; then
      writeToEliza $MSG_NDISWRAPPER_PROB $module $native
      finalrc=1;
   fi

   ndiswrapper -l | $GREP -i "driver invalid" > /dev/null
   rc=$?

   if [[ $rc == 0 ]]; then
      writeToEliza $MSG_NDISWRAPPER_FW_PROB $module
      finalrc=1;
   fi

# kernel ndiswrapper version 1.47 loaded (smp=yes)
# kernel: usb 5-7: reset high speed USB device using ehci_hcd and address 8
# kernel: ndiswrapper (check_nt_hdr:150): kernel is 64-bit, but Windows driver is not 64-bit;bad magic: 010B
# kernel: ndiswrapper (load_sys_files:216): couldn't prepare driver 'sis163u'

   if (( $USE_ROOT )); then

     $GREP -i "ndiswrapper.*bad magic.*" 2>&1 1>/dev/null $VAR_LOG_MESSAGE_FILE
      rc=$?

     if [[ $rc == 0 ]]; then
         writeToEliza $MSG_NDISWRAPPER_ARCH_PROB $module
         finalrc=1;
     fi
   else
      writeToEliza $MSG_NO_ANALYSIS_AS_USER "ndiswrapper_arch_problems"
  fi

   state "NDIS:$finalrc"
   debug "<<checkForNdisWrapperAndLinuxModule $finalrc"
return $finalrc;

}

function listLSPCIModules() {

   local i
   local j
   local matchString

   debug ">>listLSPCIModules"

   if [[ -z $1 ]]; then

      if [[ $CONNECTION == $CONNECTION_WRL ]]; then
         matchString="network.*controller|ethernet.*controller.*(wireless|802\.11)"
      else
         matchString="ethernet.*controller"
      fi

      for i in $($LSPCI -nn | $EGREP -i $matchString | $PERL -n -e '/\[(\w+:\w+)\]/; print "$1\n";'); do

        VENDORID=$(echo $i | cut -d ":" -f 1);
        DEVICEID=$(echo $i | cut -d ":" -f 2);

        echo "Available kernelmodules for VendorId:DeviceId - $i" >> $LOG

        for j in $(find /lib/modules/`uname -r` -name "*.ko") ; do \
           MODULE=${j##*/}
           MODULE=${MODULE/.ko/}
           echo "Module: $MODULE" && /sbin/modinfo "$j" | $GREP -i "$VENDORID" | $GREP -i "$DEVICEID" ; \
        done | while read ; do
              $GREP -B1 alias | head -n 1 >> $LOG
              done
      done
   else
      echo "find /lib/modules/\`uname -r\` -name \"*.ko\""
   fi

   debug "<<listLSPCIModules"

}

##################################################################################
#
# --- Extract some useful info from hwinfo (SUSE and debian only)
#
##################################################################################

function listHWInfo() {

   debug ">>listHWInfo"

   if `isCommandAvailable hwinfo`; then

      if [[ -z $1 ]]; then

         $PERL -e '

          my $MATCH = qr /Model:|Vendor:|Device:|Driver:|Driver Modules:|Subvendor:|Subdevice:|Device File:|^\d+:|Link detected|Driver Status:|Driver Activation Cmd:/;
          my $line;

            foreach $line (`'$HWINFO' --netcard`) {
               if ($line =~ /$MATCH/) {
                  print "$line";
               }
            }
         '
      else
         echo "hwinfo (filtered)"
      fi

   elif `isCommandAvailable lshw`; then

      if [[ -z $1 ]]; then
         $PERL -e '

          my $MATCH = qr /product:|vendor:|capabilities:|configuration:/;
          my $line;

            foreach $line (`'$LSHW' -C network`) {
               if ($line =~ /$MATCH/) {
                  print "$line";
               }
            }
         '
      else
         echo "lshw -C network (filtered)"
      fi

   fi

   debug "<<listHWInfo"

}

function ifConfig() {

    $PERL -e '
    my $DEVICES="^(en|wl|eth|wlan|ra|ath|dsl)";

       my $line;
       my $startSequence=0;
       foreach $line (qx %'$IFCONFIG'%) {
          if ($line =~ $DEVICES) {
             print $line;
             $startSequence=1;
          }
          elsif ($line =~ /^$/) {
             $startSequence=0;
          }
          elsif ($startSequence == 1) {
             print $line;
          }
       }
    '
}

##################################################################################
#
# --- Check whether there is a link missing on network interface
#
##################################################################################

# Device File: eth0
#  Memory Range: 0xdb800000-0xdb803fff (rw,non-prefetchable)
#  I/O Ports: 0xd800-0xd8ff (rw)
#  IRQ: 18 (126399 events)
#  HW Address: 00:0e:a6:3b:dd:06
#  Link detected: yes

function checkForMissingLink () {

   debug ">>checkForMissingLink"

   if [[ $DISTRO == $SUSE ]]; then

      if [[ $CONNECTION == $CONNECTION_WRD ]]; then
         CONN="en|eth"
         PARM="--netcard"
      else
         CONN="en|wl|eth|ath|wlan|ra"
         PARM="--wlan"
      fi

      checkForMissingLink=`$PERL -e '

          my $line;
          my $multiple=0;
          my $devices="";
          foreach $line (qx %'$HWINFO' '$PARM'%) {
               if ($line =~ /Link detected: no/) {
                  if ($device =~ '$CONN') {
                     if ($multiple eq 1) {
                        $devices="$devices,$device";
                     }
                     else {
                        $devices="$device";
                        $multiple=1;
                      }
                  }
               }
               if ($line =~ /Device File.*: ([a-z0-9]+)/) {
                  $device=$1;
               }
            }
         print $devices
         '`
   fi

   debug "<<checkForMissingLink $checkForMissingLink"

   if [ "$checkForMissingLink" != "" ]; then
      return 1
   fi
}

##################################################################################
#
# Extract some info from /etc/sysconfig/network (SUSE only)
#
##################################################################################

function listSuSEConfig() {
   local m

   debug ">>listSuSEConfig"

   if [[ $DISTRO == $SUSE ]]; then
      if [[ -z $1 ]]; then
         $EGREP -i "^[^#].*(persistent|networkmanager)" /etc/sysconfig/network/config 
      else
         m=`colorate "egrep -i \"^[^#].*(persistent|networkmanager)\" /etc/sysconfig/network/config"`
         echo $m
      fi
   fi

   debug "<<listSuSEConfig"

}

##################################################################################
#
#  -- Masquerade sensitive informations
#
##################################################################################

#
# This function masquerades mac addresses
#
# All identical macs get the same masqueraded values so xref is possible
#

function masqueradeMacs() {

   debug ">>masqueradeMACs"

   cat "$FINAL_RESULT" | $PERL -e '

   my $MAC_ADDRESS = qr /(([\da-fA-F]{2}\:){5}[\da-fA-F]{2})/;
   my $MAC_MASK="#";
   my $mac_cnt=0;
   my %macAddresses;

   while (<>) {

       $line=$_;
       pos($line)=0;

       while ($line =~ /($MAC_ADDRESS)/g) {

        my $mac = $1;
             my $privateMac = $mac;
        my $normalizedMac = uc($mac);

             if ( $macAddresses{$normalizedMac} ) {
                   $privateMac = $macAddresses{$normalizedMac};        # get masqueraded mac
             }
             else {
               $mac_cnt++;
               $privateMac =~ s/\w/$MAC_MASK/g;
   #           $privateMac =~ s/(.)./$1$MAC_MASK/g;
               $privateMac =~ s/$MAC_MASK$/$mac_cnt/;
               $macAddresses{$normalizedMac} = $privateMac;        # cache mac
             }
             s/$mac/$privateMac/;
         }
      print "$_";
   }

   exit $mac_cnt;

   ' > "$FINAL_RESULT_mm_$$"

# writeToEliza $MSG_MASQ_MAC $?

   mv "$FINAL_RESULT_mm_$$" "$FINAL_RESULT"

   debug "<<masqueradeMACs"

}

#
# This function masquerades ESSIDs
#
# All identical ESSID get the same masqueraded values so xref is possible
#

function masqueradeESSIDs() {

   debug ">>masqueradeESSIDs"

   cat "$FINAL_RESULT" | $PERL -e '

   my $ESSID_MASK="'$ESSID_MASK'";
   my $essid_cnt=0;
   my %essidAddresses;
   my $tick=chr(0x27);    # tick mark

   while (<>) {

   #         iwcsan                   ifcfg                              ssid log message
       if (/ESSID:"(.+)"/ || /WIRELESS_ESSID=${tick}(.+)${tick}/ || /--- WLAN SSID.*: (.+)/ ) {

             my $essid = $1;
             my $privateEssid = $essid;

             if ( $essidAddresses{$essid} ) {
                   $privateEssid = $essidAddresses{$essid};        # get masqueraded essid
             }
             else {
               $essid_cnt++;
               $privateEssid = "${ESSID_MASK}${essid_cnt}";
   #            $privateEssid =~ s/(.)./$1#/g;
               $essidAddresses{$essid} = $privateEssid;            # cache essid
             }
             s/$essid/$privateEssid/;
         }
      print "$_";
   }

   exit $essid_cnt;

   ' > "$FINAL_RESULT_ee_$$"

   mv "$FINAL_RESULT_ee_$$" "$FINAL_RESULT"

   debug "<<masqueradeESSIDs"

}

#
# This function masquerades IPs
#
# All private IP addresses (e.g. 192er numbers, 10er numbers etc) are NOT masqueraded
## All identical ips get the same masqueraded values so xref is possible
#

function masqueradeIPs() {

   debug ">>masqueradeIPs"

   cat "$FINAL_RESULT" | $PERL -e '

   my $IP_ADDRESS = qr /(([\d]{1,3}\.){3}[\d]{1,3})/;
   my $IP_MASK="%";
   my $ip_cnt=0;
   my %ipAddresses;
   my $line;
   my $route_flag=0;
   my $line_cnt;
   my $inBlock=0;

   while (<>) {

       if ($_ =~ "^=+.*(route|ifconfig|iwconfig|cat /etc/hosts|cat /etc/resolv|cat /etc/sysconfig/network/ifcfg)") {
         $inBlock=1;
       }
       else {
		 if ( $_ =~ "^=+" ) {                         # route block (and others) ends
			$inBlock=0;
			$route_flag=0;
		 }
       }

      if ( $inBlock == 1) {

         if ($_ =~ "^=+ route") {                      # route block starts
            $route_flag=1;
         }

         $line=$_;
         pos($line)=0;
         $line_cnt=0;

         while ($line =~ /($IP_ADDRESS)/g ) {

            if ($_ =~ "Ping of") {                         # external ping
               next;
            }

            my $ip = $1;
            $line_cnt++;

            my $privateIp = $ip;
            if ( $` =~ /Mask[e]?/) {            # skip mask in ifconfig (German and English locale)
               next;
            }

            if ($route_flag == 1 && $line_cnt==3) {      # skip mask in route command
               next;
            }

            if ( $1 !~ /^192\.168\./
               && $1 !~ /^127\./
               && $1 !~ "0\.0\.0\.0"
               && $1 !~ "255\.0\.0\.0"
               && $1 !~ "255\.255\.0\.0"
               && $1 !~ "255\.255\.255\.0"
               && $1 !~ "255\.255\.255\.255"
               && $1 !~ "^169\."
               && $1 !~ "^10\."
               && $1 !~ "^172\.([1][6-9]|2[1-9]|3[0-1])" ) {

               if ( $ipAddresses{$ip} ) {
                   $privateIp = $ipAddresses{$ip};                 # get masqueraded ip
               }
               else {
                  $ip_cnt++;
                  $privateIp =~ s/\d+\.\d+/%%%.%%%/;
   #               $privateIp =~ s/\d/$IP_MASK/g;
   #               $privateIp =~ s/$IP_MASK$/$ip_cnt/;
                  $ipAddresses{$ip} = $privateIp;                 # cache ip
               }
            s/$ip/$privateIp/;
            }
         }
     }
     print "$_";
   }

   exit $ip_cnt;

   ' > "$FINAL_RESULT_mi_$$"

   mv "$FINAL_RESULT_mi_$$" "$FINAL_RESULT"

   debug "<<masqueradeIPs"

}

#function stripWLANKeys () {
#   $PERL -e 'while (<>) {
#      if (/\S+/) {
#            print "$_";
#      }
#   }' $1
#}


##################################################################################
#
# --- Helperfunctions
#
##################################################################################

function stripEmptyLines () {
   $PERL -e 'while (<>) {
        if (/\S+/) {
                print "$_";
        }
      }' $1
}

function joinLines () {
   $PERL -e 'while (<>) {
               chomp;
               print "$_ ";
            }' $1
}

function stripWLANKeys() {

$PERL -e '

$mask="@@@@@@";
%keywords = ( "WIRELESS_KEY" => 1,              # SUSE -> /etc/sysconfig/network/ifcfg-*
             "WIRELESS_DEFAULT_KEY" => 1,
             "WIRELESS_KEY_0" =>1,
             "WIRELESS_KEY_1" =>1,
             "WIRELESS_KEY_2" =>1,
             "WIRELESS_KEY_3" =>1,
             "WIRELESS_KEY_LENGTH" =>1,
             "WIRELESS_WPA_IDENTITY" => 1,
             "WIRELESS_WPA_PASSWORD" => 1,
             "WIRELESS_WPA_PSK" => 1,
             "WIRELESS_ESSID" => 1,				# Mageia
             "KEY" => 1,                        # RedHat -> /usr/share/doc/initscripts*/sysconfig.txt
			 "WIRELESS_ENC_KEY" => 1,			
             "wpa-psk" => 1,                    # Debian -> /etc/network/interfaces
             "wpa-ssid" => 1,                 
             "wireless-key" => 1,
                                                # Arch ->
             "WLAN_KEY" => 1,                   # Slackware -> /etc/rc.d/rc.inet1.conf
             "WPAPSK" => 1,
             "ESSID" => 1,						# mageia5
             "NAME" => 1,						
        );


while (<>) {
        my ($key,$value) = /([A-Za-z0-9_\-]+)[\s=]+(.*)$/;
        if ($value) {
                if ( exists($keywords{$key})) {
                        s/\Q$value\E/$mask/;      # just to allow ? in keys as starting character
                }
        }
        print;
}' $1

}
#################################################################################
#
# NWCollect: List network configuration
#
##################################################################################

function listNetworkConfigs () {

   local cmd
   local c

   if (( ! $CONFIG_READABLE )); then
   		writeToEliza $MSG_NO_ANALYSIS_AS_USER "list_network_configuration_files"
		return 0
   fi

   cmd=('/etc/sysconfig/network/ifcfg-[earwd]*' # SUSE
        '/etc/sysconfig/network-scripts/ifcfg-[earwd]*' #REDHAT
        '/etc/network/interfaces' # DEBIAN
        '/etc/rc.conf' # ARCH
        '/etc/rc.d/rc.inet1.conf') # SLACKWARE

   if [[ -z $1 ]]; then
	
	   c=$(ls ${cmd[$DISTRO]} 2>&1 1>/dev/null)
	   if [[ "$?" = "0" ]]; then	# if there exists files
	      c="for f in \$(ls "${cmd[$DISTRO]}"); do echo \"--- \$f\"; cat \$f | "$EGREP" -v \"^#|^$\" | "$EGREP" -v \"=''\"; done"
	      eval $c | stripWLANKeys
	else
		echo "No config files found"
	fi
   else
      echo "cat ${cmd[$DISTRO]} | grep -v \"^#|^$\" | grep -v \"=''\""
   fi

}

##################################################################################
#
# Open output file if possible
#
##################################################################################

function openResultFile() {

   if [[ $CND_INTERNATIONAL_POST == "0" && $CND_OPEN_RESULT_FILE == "1" && $UID -ne 0 && $GUI -eq 0 ]]; then
      if [[ -n `which xdg-open 2>/dev/null` ]]; then
         `xdg-open "$FINAL_RESULT" 2>/dev/null &`
      fi
   fi
}

function colorate () {  # message

   local m
   local sl
   sl=${#SEPARATOR}
   m="$CMD_PREFIX $1 $SEPARATOR"

   echo ${m:0:$sl}

}


##################################################################################
#
#  --- Collect PD data
#
##################################################################################

#
# --- Commands executed collect valuable informations about the network and it's configuration
#
function collectNWData () {   #listOnly

   debug ">>collectNWData"

   # standard
   i=0;FLAG[$i]="s";MSG[$i]="cat /etc/*[-_]release || cat /etc/*[-_]version";CMD[$i]="(ls /etc/*[-_]release 2>/dev/null && cat /etc/*[-_]release) || (ls /etc/*[-_]version && cat /etc/*[-_]version)"
   i=$i+1;FLAG[$i]="s";MSG[$i]="uname -a";CMD[$i]="uname -a"
   i=$i+1;FLAG[$i]="s";MSG[$i]="";CMD[$i]="listNetworkConfigs"
#   i=$i+1;FLAG[$i]="s";MSG[$i]="";CMD[$i]="dhcpTests"
   i=$i+1;FLAG[$i]="s";MSG[$i]="ping tests";CMD[$i]="pingTests"
   i=$i+1;FLAG[$i]="s";MSG[$i]="cat /etc/resolv | grep -i \"nameserver\"";CMD[$i]="cat /etc/resolv.conf | $GREP -v \"^#\|^[ ]*$\" | $GREP -i \"nameserver\""
   i=$i+1;FLAG[$i]="s";MSG[$i]="cat /etc/hosts";CMD[$i]="cat /etc/hosts | $GREP -v \"^#\|^$\" | $GREP -v \"::\""
   i=$i+1;FLAG[$i]="s";MSG[$i]="(route -n && route -A inet6 -n) | egrep \"(en|wl|eth|ath|ra|wlan|dsl|ppp)\"";CMD[$i]="($ROUTE -n && $ROUTE -A inet6 -n) | $EGREP \"(en|wl|eth|ath|wlan|ra|dsl|ppp)\""
   i=$i+1;FLAG[$i]="s";MSG[$i]="ifconfig (filtered for en|wl|eth|wlan|ra|ath|dsl|ppp)";CMD[$i]="$IFCONFIG | awk '/^(en|wl|eth|eth|wlan|ra|ath|dsl|ppp)/ { ifc=\$1 } !NF { ifc=\"\" } ifc { print }'"
   i=$i+1;FLAG[$i]="h";MSG[$i]="lspci";CMD[$i]="$PERL -e 'qx/uname -r/ =~/(\d+)\.(\d+)/; exit  (\$1 > 2 || ( \$1 == 2 && \$2 >= 6))' || $LSPCI -nnk | $EGREP -i -A 2 '(ethernet|network)'; $PERL -e 'qx/uname -r/ =~/(\d+)\.(\d+)/; exit  (\$1 > 2 || ( \$1 == 2 && \$2 >= 6))' && $LSPCI -nn | $EGREP -i '(ethernet|network)'"
#   i=$i+1;FLAG[$i]="h";MSG[$i]="";CMD[$i]="listLSPCIModules"
   i=$i+1;FLAG[$i]="h";MSG[$i]="lsusb | grep -v \"root hub\"";CMD[$i]="which lsusb 2>/dev/null 1>&2 && lsusb | $GREP -v \"root hub\";which lsusb 2>/dev/null 1>&2 || echo \"lsusb not available. usbutils package needs to be installed\""
   i=$i+1;FLAG[$i]="h";MSG[$i]="";CMD[$i]="listHWInfo"
   i=$i+1;FLAG[$i]="h";MSG[$i]="lsmod (filtered)";CMD[$i]="listLoadedModules"
   i=$i+1;FLAG[$i]="w";MSG[$i]="iwconfig";CMD[$i]="$IWCONFIG 2>&1 | awk '/^(en|wl|eth|wlan|ra|ath|dsl|ppp)/ { ifc=\$1 } !NF { ifc=\"\" } ifc { print }' | $SED \"s/\(Encryption key:\)\([^o][^f][^f][^ ]*\)\(.*\)/\1@@ @@@-@@@@-@@@@-@@@@-   @@@@-@@@@@@@\3/\"" 
   i=$i+1;FLAG[$i]="w";MSG[$i]="";CMD[$i]="listFirmware"
   i=$i+1;FLAG[$i]="w";MSG[$i]="iwlist scanning (filtered)";CMD[$i]="detectAPs"
   i=$i+1;FLAG[$i]="w";MSG[$i]="ndiswrapper -l";CMD[$i]="( $LSMOD | $GREP -i ndiswrapper > /dev/null ) && ndiswrapper -l; ( $LSMOD | $GREP -i ndiswrapper > /dev/null ) || echo \"No ndiswrapper module loaded\""
   i=$i+1;FLAG[$i]="w";MSG[$i]="Active processes";CMD[$i]="listActiveProcesses"
   i=$i+1;FLAG[$i]="w";MSG[$i]="";CMD[$i]="listWPAProcesses"
   i=$i+1;FLAG[$i]="w";MSG[$i]="";CMD[$i]="listSuSEConfig"
   i=$i+1;FLAG[$i]="w";MSG[$i]="";CMD[$i]="listrfkill"
   i=$i+1;FLAG[$i]="w";MSG[$i]="Actual date for bias of following greps";CMD[$i]="echo \"`date +\"%T %F\"`\" 1>&2"
   i=$i+1;FLAG[$i]="w";MSG[$i]="grep -i radio ${VAR_LOG_MESSAGE_FILE} | tail -n 5";CMD[$i]="[ $UID -eq 0 ] && ( $GREP -i radio ${VAR_LOG_MESSAGE_FILE} | $TAIL -n 5 ); [ $UID -ne 0 ] && echo \"??? Unable to access ${VAR_LOG_MESSAGE_FILE} to check for WLAN errors as normal user\""
   i=$i+1;FLAG[$i]="w";MSG[$i]="dmesg | grep -i radio | tail -n 5";CMD[$i]="dmesg | $GREP -i radio | $TAIL -n 5"
   i=$i+1;FLAG[$i]="w";MSG[$i]="tail -n $NUMBER_OF_LINES_TO_CHECK_IN_VAR_LOG_MESSAGES ${VAR_LOG_MESSAGE_FILE} | $GREP -i firmware | tail -n 10";CMD[$i]="[ $UID -eq 0 ] && (tail -n $NUMBER_OF_LINES_TO_CHECK_IN_VAR_LOG_MESSAGES ${VAR_LOG_MESSAGE_FILE} | $GREP -i firmware | $TAIL -n 10); [ $UID -ne 0 ] && echo \"??? Unable to access ${VAR_LOG_MESSAGE_FILE} to check for firmware errors as normal user\""
   i=$i+1;FLAG[$i]="s";MSG[$i]="egrep 'en|wl|eth|ath|wlan|ra|ppp' /etc/udev/rules.d/*net_persistent* /etc/udev/rules.d/*persistent-net*";CMD[$i]="$EGREP 'en|wl|eth|ath|wlan|ra|ppp' /etc/udev/rules.d/*net_persistent* /etc/udev/rules.d/*persistent-net* 2>/dev/null | $GREP -v \":#\|:$\" 2>/dev/null"
   i=$i+1;FLAG[$i]="w";MSG[$i]="egrep -r '(en.*|wl.*|eth|ath|wlan|ra)[0-9]+' /etc/modprobe.*|egrep -v -i '#|blacklist'";CMD[$i]="$EGREP -r '(en.*|wl.*|eth|ath|wlan|ra)[0-9]+' /etc/modprobe.*|$EGREP -v -i '#|blacklist'"
   i=$i+1;FLAG[$i]="f";MSG[$i]="arp -n";CMD[$i]="$ARP -n"
   i=$i+1;FLAG[$i]="f";MSG[$i]="iptables -L -vn";CMD[$i]="$IPTABLES -L -vn"
   i=$i+1;FLAG[$i]="f";MSG[$i]="cat /etc/sysconfig/SuSEfirewall2";CMD[$i]="cat /etc/sysconfig/SuSEfirewall2 | $GREP -v \"^#\|^$\""
   i=$i+1;FLAG[$i]="f";MSG[$i]="cat /proc/sys/net/ipv4/ip_forward";CMD[$i]="cat /proc/sys/net/ipv4/ip_forward"

   # count number of eligible tests

   NUMBER_OF_TESTS=0
   i=0
   while [ -n "${CMD[$i]}" ]; do
      R=`echo $FLAGS | grep "${FLAG[$i]}"`
      if [[ $? == 0 ]]; then
         let NUMBER_OF_TESTS=NUMBER_OF_TESTS+1
      fi
      let i=i+1
   done

   i=0      # counter of all possible tests
   pi=0      # counter of eligible tests

   # process tests and print progress in percent

   while [ -n "${CMD[$i]}" ]; do

   #   echo $FLAGS ${FLAG[$i]}
      R=`echo $FLAGS | grep "${FLAG[$i]}"`

      if [[ $? == 0 ]]; then
   #      fill log file with information
         debug "*** ${CMD[$i]} "
         if [[ -z ${MSG[$i]} ]]; then
            msg=`eval ${CMD[$i]} m`
            if [[ -z $msg ]]; then         # no report for this distro
               let i=i+1
               let pi=pi+1
               continue
            fi
   #         echo $SEPARATOR >> $LOG
   #         echo "*** $msg" >> $LOG
            set -f
            header=`colorate "$msg"`
            echo $header >> $LOG
            debug "-- $msg"
            set +f
         else
   #         echo $SEPARATOR >> $LOG
   #         echo "*** ${MSG[$i]}" >> $LOG
            set -f
            header=`colorate "${MSG[$i]}"`
            echo $header >> $LOG
            debug "-- ${MSG[$i]}"
            set +f
         fi
         processingMessage $pi $NUMBER_OF_TESTS $msg
         eval ${CMD[$i]} 2>> $LOG 1>> $LOG
         let pi=pi+1
      fi
      let i=i+1

   done
   processingMessage $NUMBER_OF_TESTS $NUMBER_OF_TESTS   # display 100%
   sleep 1
   processingMessage -1               # clean output area now
   debug "<<collectNWData"
}

# help text

function usage () { # exitcode

   echo -e $VERSION_STRING 
   echo ""
   echo $LICENSE
   echo "Analyze system for common network configuration problems"
   echo "and collect network problem determination information for futher problem determination"
   echo "Invocation: $MYSELF"
   echo "Parameters:"
   echo "-c : Connection (1-2)"
   echo "-d : Write debug messages"
   echo "-e : ESSID used for WLAN"
   echo "-f : Collect info for routers, i.e. firewall rules, firewall configurations etc"
   echo "-g : script called by GUI wrapper"
   echo "-h : Print this help message"
   echo "-i : International posting"
   echo "-m : Turn MAC masquerading off"
   echo "-n : Turn NWEliza off"
   echo "-o : Executionhost (1-2)"
   echo "-p filename : Filename of result file (default: collectNWData.txt)"
   echo "-r : Invoke script as root"
   echo "-s : Don't open resultfile in editor"
   echo "-t : Topology (1-4)"
   echo "-u : Don't run script as root"
   echo "-v : Print script version"    
   echo "-x : Trace script flow. Creates huge output"

   if [[ -z $1 ]]; then
      exit 0
   else
      exit $1
   fi
}

#################################################################################
#################################################################################
#################################################################################
####
####                                 main
####
#################################################################################
#################################################################################
#################################################################################

queryDistro

# modules are not known right now - just use plain bash commands

##################################################################################
#
# handle invocation options
#
##################################################################################

# defaults

DEBUG="off"				# debug messages
TRACE=0				# detailed trace (-x -v)
FLAGS="-shc"                	# default flags
opt="$@"
NWELIZA_ENABLED=1             # enabled for all distros
USE_ROOT=1                    # default: Call script as root
USE_USER_AS_PARM=0
CND_OPEN_RESULT_FILE=1
MASQUERADE_MAC=1
ROOTOPTION=0
CONNECTIONTYPEOPTION=0
EXECUTIONHOSTOPTION=0
ESSIDOPTION=""
INTERNATIONALOPTION=0
GUI=0
CLEANUP=0
CLEANALL=0

# parse args
while getopts ":a :c: :d :e: :f :g :h :i :k :l :m :n :o: :p: :r :s :t: :u :v :x" opt
do 
   case "$opt" in
   a) CLEANALL=1;;
   c) CONNECTIONTYPEOPTION=$OPTARG
      if [[ $OPTARG < 1 || $OPTARG > 2 ]]; then
         echo "Argument for option -$opt should be 1 or 2"
         exit 127
      fi;;
   d) DEBUG="on";;
   e) ESSIDOPTION=$OPTARG;;
   f) FLAGS="${FLAGS}f";;
   g) GUI=1
      VERSION_STRING="$VERSION_STRING -iGUI-";;
   h) usage 127;;
   i) INTERNATIONALOPTION=1;;
   k) CLEANUP=1;;
   m) MASQUERADE_MAC=0;;
   n) NWELIZA_ENABLED=0;;
   o) EXECUTIONHOSTOPTION=$OPTARG
      if [[ $OPTARG < 1 || $OPTARG > 2 ]]; then
         echo "Argument for option -$opt should be 1 or 2"
         exit 127
      fi;;
   p) OUTPUT_FILE=$OPTARG;;
   r) ROOTOPTION=1;;
   s) CND_OPEN_RESULT_FILE=0;;
   t) TOPOLOGYTYPEOPTION=$OPTARG
      if [[ $OPTARG < 1 || $OPTARG > 4 ]]; then
         echo "Argument for option -$opt should be 1,2,3 or 4"
         exit 127
      fi;;
   u) USE_USER_AS_PARM=1;;
   v) echo -e $VERSION_STRING;
	  echo ""
	  echo $LICENSE
      exit 0;;
   \?) echo "Unknown option \"-$OPTARG\"."
         usage 1;;
   :) echo "Option \"-$OPTARG\" requires an argument."
         usage 127;;
    esac
done

#################################################################################
# Cleanup function for GUI
#################################################################################

if [[ $GUI -ne 0 && $CLEANUP -ne 0 ]]; then
   cleanupTempFiles
   exit 0
fi

if [[ $GUI -ne 0 && $CLEANALL -ne 0 ]]; then
   cleanupFiles
   exit 0
fi


#################################################################################
# Make sure script runs in a console
#################################################################################

if [[ $GUI -eq 0 ]]; then
   tty -s;
   if [ $? -ne 0 ]; then
   #  konsole --noclose -T "collectNWData.sh" --vt_sz 132x25 -e "$0";
     konsole -e "$0"
     exit;
   fi
fi

if [[ $CND_VERSION_STRING == "" ]]; then
   echo
   echo -e $VERSION_STRING
   echo
   echo $LICENSE
   echo
   export CND_VERSION_STRING=$VERSION_STRING
   isLanguageSupported
   rc=$?
   if (( ! $rc )); then
      writeToConsole $MSG_ASK_FOR_XLATION
      writeToConsole $MSG_EMPTY_LINE
   fi
fi

if (( ! $USE_USER_AS_PARM )); then      # invocation not as normal user requested
   if [ $UID -eq 0 -o $ROOTOPTION == "1" ]; then         # invoked by root already of root option selected
      USE_ROOT=1
   else
      USE_ROOT=0
      if [[ $GUI -eq 0 ]]; then      
      	 yes=`getLocalizedMessage $MSG_ANSWER_CHARS_YES`
      	 no=`getLocalizedMessage $MSG_ANSWER_CHARS_NO`
      	 answer=""            # ask user for his choice
      	 while [[ $answer == "" ]]; do
	        writeToConsoleNoNL $MSG_ASK_FOR_ROOT
     	    read a
         	if [[ $a == "" ]]; then
            	answer=${yes:0:1}      # default
         	else
            	case "$a" in
               	[$yes]) answer=${yes:0:1};;
               	[$no]) answer=${no:0:1};;
            	esac
         	fi
      	done
      	if [[ $answer == ${yes:0:1} ]]; then
        	 USE_ROOT=1
      	fi
      fi
   fi
else
   USE_ROOT=0
fi

if [[ $CND_INTERNATIONAL_POST == "" ]]; then

   CND_INTERNATIONAL_POST=0
   if (( $INTERNATIONALOPTION )); then
      CND_INTERNATIONAL_POST=1
   else
      if [[ $GUI -eq 0 ]]; then         
      	 isLanguageSupportedAndNotEnglish
         lsup=$?
      	 if (( $lsup )); then
         	yes=`getLocalizedMessage $MSG_ANSWER_CHARS_YES`
         	no=`getLocalizedMessage $MSG_ANSWER_CHARS_NO`
         	answer=""            # ask user for his choice
         	while [[ $answer == "" ]]; do
            	writeToConsoleNoNL $MSG_ASK_LANG
            	read a
            	if [[ $a == "" ]]; then
               		answer=${no:0:1}  # default
            	else
               		case "$a" in
                  		[$yes]) answer=${yes:0:1};;
                  		[$no]) answer=${no:0:1};;
             		esac
            	fi
         	done
         	if [[ $answer == ${yes:0:1} ]]; then
            	CND_INTERNATIONAL_POST=1
         	fi
         fi
      fi
   fi
fi

#  invoke script as root if requested

if (( $USE_ROOT )); then
   if [ $UID -ne 0 ]; then
      INVOCATION_DIR=`pwd`

      export CND_USER=$USER
      export CND_OPEN_RESULT_FILE=$CND_OPEN_RESULT_FILE
      export CND_INTERNATIONAL_POST=$CND_INTERNATIONAL_POST

      if which sudo &> /dev/null; then
         debug "Starting sudo as $USER ..."
     	 sudo -p "Enter password of user %p" -E "$0" $*            # try sudo first
         if [ $? == 1 ]; then         # failure
            writeToConsole $MSG_MAIN_BECOME_ROOT
            debug "Starting su1 as $USER ..."
            su -p -c "$0 $*"   # now use su, dont suppress &2 (pwd prompt)
         fi
      else
         writeToConsole $MSG_MAIN_BECOME_ROOT
         debug "Starting su2 as $USER ..."
         su -p -c "$0 $*"   # now use su, dont suppress &2 (pwd prompt)
      fi
      openResultFile
      exit $?
   fi
fi

shift $(($OPTIND - 1))            # pop invocation parms

# check whether all required progs are available and locate their path
# set uppercase vars of command to fq path

MODS="$MODS_ALL $MODS_OPT"

MODS_MISSING_LIST=""
MODS_MISSING=0

for mod in $MODS; do
#   echo "--------- $mod"
   # prog name in lower case
   lwr=`echo $mod | perl -e "print lc(<>);"`
   mod=`echo $mod | sed 's/-/_/'`
   # store detected path
   p=`find {/sbin,/usr/bin,/usr/sbin,/bin} -name $lwr | head -n 1`
   eval "$mod=\"${p}\""
   eval "c=\${${mod}}"
#   echo "------m $mod"
#   echo "------c $c"
   if [ ! -x "$c" ]; then
#        echo "--???-- $mod"
	if [[ "$MODS_ALL" == *"$mod"* ]]; then
#            echo "--!!!-- $mod"
            if [ -z $MODS_MISSING_LIST ]; then
               MODS_MISSING_LIST=$lwr
            else
               MODS_MISSING_LIST="$MODS_MISSING_LIST,$lwr"
	    fi
            MODS_MISSING=1
	 fi
    fi
done

if (($MODS_MISSING)); then
      writeToConsole $MSG_MAIN_PROG_REQUIRED $MODS_MISSING_LIST
      exit 127
fi

if [[ $TRACE != 0 ]]; then
   set -o verbose
   set -o xtrace
fi

#################################################################################
# --- Now do your job
#################################################################################

if [[ -e "$FINAL_RESULT" ]]; then

   rm "$FINAL_RESULT" 2>/dev/null

   if [ $? != 0 ]; then
      echo "Can't delete $FINAL_RESULT"
      exit 255
   fi
fi

rm -f "$CONSOLE_RESULT" 2>/dev/null
rm -f "$ELIZA_RESULT" 2>/dev/null
rm -f "$COLLECT_RESULT" 2>/dev/null

echo $CODE_BEGIN >> "$FINAL_RESULT"

echo "$VERSION_STRING" >> "$FINAL_RESULT"
echo "" >> "$FINAL_RESULT"
echo "$LICENSE" >> "$FINAL_RESULT"

if [[ $DISTRO == $UNKNOWN_DISTRO ]]; then
   echo $MSG_DISTRO_NOT_SUPPORTED
   exit 127
fi

if [[ $DISTRO == $SUSE ]]; then
   NWELIZA_ENABLED=1
fi

if (( ! $USE_ROOT && ! $GUI )); then
   writeToEliza $MSG_EMPTY_LINE
   writeToEliza $MSG_ANALYSIS_AS_USER
fi

getConnection
getTopology
getExecutionHost
getESSID

# check some environmental stuff

PNINused
configReadable

writeToEliza $MSG_EMPTY_LINE
writeToEliza $MSG_START_COLLECTING $FINAL_RESULT_SHORT_NAME

detectInterfaces
collectNWData
writeToEliza $MSG_EMPTY_LINE

if (( $NWELIZA_ENABLED )); then
   writeToEliza $MSG_ELIZA_START_ANALYZE
   NWEliza
else
   writeToEliza $MSG_NWELIZA_UNAVAILABLE
fi

state "GUI:$GUI"
state "UID:$UID"

#################################################################################
# --- Paperwork
#################################################################################

if [[ $CONNECTION == $CONNECTION_WRL ]]; then
   writeToEliza $MSG_CHECK_KEYS $FINAL_RESULT_SHORT_NAME
fi

if (( $NWELIZA_ENABLED )); then

   if [[ $askEliza_error == 0 && $askEliza_warning == 0 ]]; then
      writeToEliza $MSG_EMPTY_LINE
      writeToEliza $MSG_MAIN_NO_ERROR_DETECTED $FINAL_RESULT_SHORT_NAME
   else
      writeToEliza $MSG_EMPTY_LINE
      writeToEliza $MSG_MAIN_GOTO_LINK
   fi
fi

writeToEliza $MSG_EMPTY_LINE
writeToEliza $MSG_MAIN_POST_FILE $FINAL_RESULT_SHORT_NAME
writeToEliza $MSG_EMPTY_LINE

if (( $NWELIZA_ENABLED )); then
   cat "$ELIZA_RESULT" >> "$FINAL_RESULT"
   echo $SEPARATOR >> "$FINAL_RESULT"
fi

cat $LOG >> "$FINAL_RESULT"

if (( $NWELIZA_ENABLED )); then
   echo "$SEPARATOR" >> "$FINAL_RESULT"
   echo "*** `NWElizaStates m`" >> "$FINAL_RESULT"
   echo "`NWElizaStates`" >> "$FINAL_RESULT"
fi

echo $CODE_END >> "$FINAL_RESULT"

#
# masquerade IPs and macs
#

if (( MASQUERADE_MAC )); then
   masqueradeMacs
fi

masqueradeIPs
masqueradeESSIDs

#       give ownership of file back to user

if [[ $UID -eq 0 && $CND_USER != "" ]]; then
   if [ $CND_USER != "root" ]; then
        chown $CND_USER.users "$FINAL_RESULT"                   # give created file back to owner
   fi
fi

# delete all temporary files

if [[ $GUI -eq 0 ]]; then
   cleanupTempFiles
fi

#

if [[ -n $OUTPUT_FILE ]]; then
   OUTPUT_FILE="collectNWData_${OUTPUT_FILE}${FLAGS}.txt"
   mv "$FINAL_RESULT" "$OUTPUT_FILE"
   FINAL_RESULT="$OUTPUT_FILE"
fi

openResultFile

if [[ $UID -eq 0 ]]; then
   export CND_INTERNATIONAL_POST=$CND_INTERNATIONAL_POST
fi

# vim: tabstop=4:softtabstop=4:shiftwidth=4:noexpandtab:syntax=sh 
