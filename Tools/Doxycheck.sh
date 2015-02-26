#!/bin/bash -e
########################################################################################################################
# Sourcen untersuchen auf Korrektheit der Doxygen Kommentare
#-----------------------------------------------------------------------------------------------------------------------
# \project    Multithreaded C++ Framework
# \file       Doxycheck.sh
# \creation   2015-02-26, Joe Merten
#-----------------------------------------------------------------------------------------------------------------------
# Achtung: Wegen bash -e sollte in diesem Skript weder "let" noch "expr" verwendet serden. ((i++)) ist ebenfalls problematisch.
# Workaround: "||:" dahinter schreiben, also z.B.:
#   let 'i++' ||:
# Siehe auch: http://unix.stackexchange.com/questions/63166/bash-e-exits-when-let-or-expr-evaluates-to-0
#-----------------------------------------------------------------------------------------------------------------------
# Status: Sehr unfertig
########################################################################################################################


########################################################################################################################
#    ____ _       _           _
#   / ___| | ___ | |__   __ _| |
#  | |  _| |/ _ \| '_ \ / _` | |
#  | |_| | | (_) | |_) | (_| | |
#   \____|_|\___/|_.__/ \__,_|_|
########################################################################################################################

########################################################################################################################
# Konstanten & Globale Variablen
########################################################################################################################

declare DIRS=()
declare FILE_PATTERNS=()

########################################################################################################################
#    ____      _
#   / ___|___ | | ___  _ __
#  | |   / _ \| |/ _ \| '__|
#  | |__| (_) | | (_) | |
#   \____\___/|_|\___/|_|
########################################################################################################################

########################################################################################################################
# Die 16 Html Farbnamen
########################################################################################################################

declare ESC=$'\e'
#declare ESC="$(printf "\x1B")"
declare   BLACK="${ESC}[0m${ESC}[30m"           #     BLACK
declare  MAROON="${ESC}[0m${ESC}[31m"           #       RED
declare   GREEN="${ESC}[0m${ESC}[32m"           #     GREEN
declare   OLIVE="${ESC}[0m${ESC}[33m"           #     BROWN -> Dunkelgelb
declare    NAVY="${ESC}[0m${ESC}[34m"           #      BLUE
declare  PURPLE="${ESC}[0m${ESC}[35m"           #   MAGENTA
declare    TEAL="${ESC}[0m${ESC}[36m"           #      CYAN
declare  SILVER="${ESC}[0m${ESC}[37m"           #    LTGRAY -> Dunkelweiss
declare    GRAY="${ESC}[0m${ESC}[30m${ESC}[1m"  #      GRAY -> Hellschwarz
declare     RED="${ESC}[0m${ESC}[31m${ESC}[1m"  #     LTRED
declare    LIME="${ESC}[0m${ESC}[32m${ESC}[1m"  #   LTGREEN
declare  YELLOW="${ESC}[0m${ESC}[33m${ESC}[1m"  #    YELLOW
declare    BLUE="${ESC}[0m${ESC}[34m${ESC}[1m"  #    LTBLUE
declare FUCHSIA="${ESC}[0m${ESC}[35m${ESC}[1m"  # LTMAGENTA
declare    AQUA="${ESC}[0m${ESC}[36m${ESC}[1m"  #    LTCYAN
declare   WHITE="${ESC}[0m${ESC}[37m${ESC}[1m"  #     WHITE
declare  NORMAL="${ESC}[0m"
declare   LIGHT="${ESC}[1m"

########################################################################################################################
# Falls keine Ansi VT100 Farben gewünscht sind
#-----------------------------------------------------------------------------------------------------------------------
# Todo: Folgendes mal genauer angucken: http://stackoverflow.com/questions/64786/error-handling-in-bash
#     Color the output if it's an interactive terminal
#    test -t 1 && tput bold; tput setf 4                                 ## red bold
#    echo -e "\n(!) EXIT HANDLER:\n"
########################################################################################################################
function NoColor {
    BLACK=""; MAROON=""; GREEN=""; OLIVE=""; NAVY=""; PURPLE="" TEAL="" SILVER=""; GRAY=""
    RED=""; LIME=""; YELLOW=""; BLUE=""; FUCHSIA=""; AQUA=""; WHITE=""; NORMAL=""; LIGHT=""
    LOG_COLOR_FATAL=""; LOG_COLOR_ERROR=""
    LOG_COLOR_WARN="";  LOG_COLOR_INFO=""
    LOG_COLOR_DEBUG=""; LOG_COLOR_TRACE=""
}


########################################################################################################################
#   _____                    _   _
#  | ____|_  _____ ___ _ __ | |_(_) ___  _ __  ___
#  |  _| \ \/ / __/ _ \ '_ \| __| |/ _ \| '_ \/ __|
#  | |___ >  < (_|  __/ |_) | |_| | (_) | | | \__ \
#  |_____/_/\_\___\___| .__/ \__|_|\___/|_| |_|___/
#                     |_|
########################################################################################################################

# siehe auch http://stackoverflow.com/questions/64786/error-handling-in-bash
# Ohne "errtrace" wird mein OnError() nicht immer gerufen...
set -o pipefail  # trace ERR through pipes
set -o errtrace  # trace ERR through 'time command' and other functions
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value

########################################################################################################################
# Terminalfarben restaurieren, ggf. Childprozesse beenden et cetera
########################################################################################################################
declare SHUTTING_DOWN=
function StopScript {
    SHUTTING_DOWN="true"
    local exitcode="$1"

    echo -n "${NORMAL}"
    echo -n "${NORMAL}" >&2

    # Kill, um ggf. gestartete Background Childprozesse auch zu beenden
    trap SIGINT
    kill -INT 0
    exit $exitcode
}

########################################################################################################################
# Terminalfarben restaurieren, wenn Abbruch via Ctrl+C
########################################################################################################################
function OnCtrlC {
    [ "$SHUTTING_DOWN" != "" ] && return 0
    echo "${RED}[*** interrupted ***]${NORMAL}" >&2
    # damit bei Ctrl+C auch alle Childprozesse beendet werden etc.
    StopScript 2
}
trap OnCtrlC SIGINT


########################################################################################################################
# Fehlerbehandlung Hook
#-----------------------------------------------------------------------------------------------------------------------
# Da wir das Skript mit "bash -e" ausführen, führt jeder Befehls- oder Funktionsaufruf, der mit !=0 returniert zu einem
# Skriptabbruch, sofern der entsprechende Exitcode nicht Skriptseitig ausgewertet wird.
# Siehe auch http://wiki.bash-hackers.org/commands/builtin/set -e
# Mit dem OnError() stellen wir hier noch mal einen Fuss in die Tür um genau diesen Umstand (unerwartete Skriptbeendigung)
# sichtbar zu machen.
########################################################################################################################
function OnError() {
    echo "${RED}Script error exception in line $1, exit code $2${NORMAL}" >&2

    # Stacktrace ausgeben
    # http://wiki.bash-hackers.org/commands/builtin/caller
    # http://stackoverflow.com/questions/685435/bash-stacktrace
    local i=0;
    local s=""
    echo -n "${MAROON}" >&2
    while s="$(caller $i)"; do
        echo "  ${MAROON}$s${NORMAL}" >&2
        ((i++)) ||:
    done
    StopScript 2
}
trap 'OnError $LINENO $?' ERR


########################################################################################################################
# Exit-Hook
#-----------------------------------------------------------------------------------------------------------------------
# OnExit() wird bei jeder Art der Skriptbeendigung aufgerufen, ggf. nach OnError()
# Siehe auch http://wiki.bash-hackers.org/commands/builtin/trap
#
# TODO: Näher untersuchen und für mich anpassen
#   tempfiles=( )
#   cleanup() {
#       rm -f "${tempfiles[@]}"
#   }
#   trap cleanup EXIT
########################################################################################################################
function OnExit() {
    local exitcode="$1"
        if [ "$2" != "0" ]; then
        echo "${RED}Script exitcode=$exitcode${NORMAL}" >&2
    else
        : # echo "${TEAL}Script exitcode=$exitcode${NORMAL}" >&2
    fi
    # TODO: Hier wirklich noch mal exit aufrufen?
    StopScript $exitcode
}
trap 'OnExit $LINENO $?' EXIT


########################################################################################################################
#   _____                        ___     _                      _
#  | ____|_ __ _ __ ___  _ __   ( _ )   | |    ___   __ _  __ _(_)_ __   __ _
#  |  _| | '__| '__/ _ \| '__|  / _ \/\ | |   / _ \ / _` |/ _` | | '_ \ / _` |
#  | |___| |  | | | (_) | |    | (_>  < | |__| (_) | (_| | (_| | | | | | (_| |
#  |_____|_|  |_|  \___/|_|     \___/\/ |_____\___/ \__, |\__, |_|_| |_|\__, |
#                                                   |___/ |___/         |___/
########################################################################################################################

########################################################################################################################
# Fehlerbehandlung & Logging
########################################################################################################################

declare LOG_COLOR_FATAL="${RED}"
declare LOG_COLOR_ERROR="${MAROON}"
declare  LOG_COLOR_WARN="${YELLOW}"
declare  LOG_COLOR_INFO="${TEAL}"
declare LOG_COLOR_DEBUG="${GREEN}"
declare LOG_COLOR_TRACE="${BLUE}"

function Fatal {
    echo "${LOG_COLOR_FATAL}*** Fatal: $*${NORMAL}" >&2
    StopScript 2
    echo "+++++++++++++++++++++++++++++++"
}

function Error {
    echo "${LOG_COLOR_ERROR}*** Error: $*${NORMAL}" >&2
}

function Warning {
    echo "${LOG_COLOR_WARN}Warning: $*${NORMAL}" >&2
}


function Info {
    echo "${LOG_COLOR_INFO}Info: $*${NORMAL}"
}

function Debug {
    echo "${LOG_COLOR_DEBUG}Debug: $*${NORMAL}" >&2
}

function Trace {
    echo "${LOG_COLOR_TRACE}Trace: $*${NORMAL}" >&2
}


########################################################################################################################
#   _____         _   _
#  |_   _|__  ___| |_(_)_ __   __ _
#    | |/ _ \/ __| __| | '_ \ / _` |
#    | |  __/\__ \ |_| | | | | (_| |
#    |_|\___||___/\__|_|_| |_|\__, |
#                             |___/
#-----------------------------------------------------------------------------------------------------------------------
# Ein Miniatur Testframework für Shellskripte
########################################################################################################################

########################################################################################################################
# Stringvergleich
#-----------------------------------------------------------------------------------------------------------------------
# \in  actual    Erhaltener Wert
# \in  expected  Erwarteter Wert
#-----------------------------------------------------------------------------------------------------------------------
# Vergleiche die beiden übergebenen Strings und gibt bei Ungleichheit eine Fehlermeldung aus
########################################################################################################################
function Test_Check {
    local actual="$1"
    local expected="$2"
    if [ "$actual" != "$expected" ]; then
        Error "Test failed. Expected \"$expected\" but got \"$actual\" from $(caller)."
    fi
}


########################################################################################################################
#   _   _ _   _ _ _ _
#  | | | | |_(_) (_) |_ _   _
#  | | | | __| | | | __| | | |
#  | |_| | |_| | | | |_| |_| |
#   \___/ \__|_|_|_|\__|\__, |
#                       |___/
########################################################################################################################

########################################################################################################################
# Hilfsfunktion: Numerischen Wert mit Tausenderpunkten ausgeben
#-----------------------------------------------------------------------------------------------------------------------
# \in  valueString  String, in dem die Tausenderseparatoren eingefügt werden sollen
# \in  minLength    Mindestlänge, Rückgabestring wird ggf. rechtsbündig formatiert
########################################################################################################################
function WithDots {
    local RET="$1"
    local IDX
    local VORZ=""

    # Vorzeichen extrahieren
    if [ "${RET:0:1}" == "-" ] || [ "${RET:0:1}" == "+" ]; then
        VORZ="${RET:0:1}"
        RET=${RET:1}
    fi

    IDX=${#RET}

    # Dots einfügen
    while [ "$IDX" -gt "3" ]; do
        let "IDX -= 3" ||:
        L=${RET:0:$IDX}
        R=${RET:$IDX}
        RET="$L.$R"
    done

    RET="$VORZ$RET"

    if [ "$#" == "2" ]; then
        # String auf Mindestlänge formatieren
        while [ "${#RET}" -lt "$2" ]; do
            RET=" $RET"
        done
    fi

    echo "$RET"
}

function Test_WithDots {
    Test_Check "$(WithDots           "")"              ""
    Test_Check "$(WithDots          "0")"             "0"

    Test_Check "$(WithDots          "1")"             "1"
    Test_Check "$(WithDots         "12")"            "12"
    Test_Check "$(WithDots        "133")"           "133"
    Test_Check "$(WithDots       "1234")"         "1.234"
    Test_Check "$(WithDots      "12345")"        "12.345"
    Test_Check "$(WithDots     "123456")"       "123.456"
    Test_Check "$(WithDots    "1234567")"     "1.234.567"
    Test_Check "$(WithDots   "12345678")"    "12.345.678"
    Test_Check "$(WithDots  "123456789")"   "123.456.789"

    Test_Check "$(WithDots         "-1")"            "-1"
    Test_Check "$(WithDots        "-12")"           "-12"
    Test_Check "$(WithDots       "-133")"          "-133"
    Test_Check "$(WithDots      "-1234")"        "-1.234"
    Test_Check "$(WithDots     "-12345")"       "-12.345"
    Test_Check "$(WithDots    "-123456")"      "-123.456"
    Test_Check "$(WithDots   "-1234567")"    "-1.234.567"
    Test_Check "$(WithDots  "-12345678")"   "-12.345.678"
    Test_Check "$(WithDots "-123456789")"  "-123.456.789"

    Test_Check "$(WithDots         "+1")"            "+1"
    Test_Check "$(WithDots        "+12")"           "+12"
    Test_Check "$(WithDots       "+133")"          "+133"
    Test_Check "$(WithDots      "+1234")"        "+1.234"
    Test_Check "$(WithDots     "+12345")"       "+12.345"
    Test_Check "$(WithDots    "+123456")"      "+123.456"
    Test_Check "$(WithDots   "+1234567")"    "+1.234.567"
    Test_Check "$(WithDots  "+12345678")"   "+12.345.678"
    Test_Check "$(WithDots "+123456789")"  "+123.456.789"

    Test_Check "$(WithDots      "12345" 9)"   "   12.345"
    Test_Check "$(WithDots     "-12345" 9)"   "  -12.345"
    Test_Check "$(WithDots     "+12345" 9)"   "  +12.345"
}
#Test_WithDots


########################################################################################################################
# Hilfsfunktion: Trim Strings
#-----------------------------------------------------------------------------------------------------------------------
# siehe auch: http://stackoverflow.com/questions/369758/how-to-trim-whitespace-from-bash-variable
########################################################################################################################
function Trim {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo "$var"
}

function TrimLeft {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    echo "$var"
}

function TrimRight {
    local var="$1"
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo "$var"
}

function Test_Trim {
    Test_Check "$(Trim        "")"              ""
    Test_Check "$(TrimLeft    "")"              ""
    Test_Check "$(TrimRight   "")"              ""

    Test_Check "$(Trim           "a b c")"                 "a b c"
    Test_Check "$(TrimLeft       "a b c")"                 "a b c"
    Test_Check "$(TrimRight      "a b c")"                 "a b c"

    Test_Check "$(Trim        "   d e f")"                 "d e f"
    Test_Check "$(TrimLeft    "   d e f")"                 "d e f"
    Test_Check "$(TrimRight   "   d e f")"              "   d e f"

    Test_Check "$(Trim           "g h i   ")"              "g h i"
    Test_Check "$(TrimLeft       "g h i   ")"              "g h i   "
    Test_Check "$(TrimRight      "g h i   ")"              "g h i"

    Test_Check "$(Trim        "   j k l   ")"              "j k l"
    Test_Check "$(TrimLeft    "   j k l   ")"              "j k l   "
    Test_Check "$(TrimRight   "   j k l   ")"           "   j k l"
}
#Test_Trim

########################################################################################################################
# Ermittlung von File Base oder Ext
#-----------------------------------------------------------------------------------------------------------------------
# \in  filename  Kompletter Dateiname, optional mit Verzeichnis
# \in  mode      - "base" = File Base wird ermittelt
#                - "ext"  = File Ext wird ermittelt
########################################################################################################################
function GetFileBaseExt {
    local filename="$1"
    local mode="$2"
    local name="$(basename "$filename")"

    # Vorabprüfung: Eine Fileext ist nur enthalten, wenn der String einen Punkt enthält, vor diesem aber eine "nicht-Punkt" ist
    if ! [[ "$name" =~ [^.]\. ]]; then
        [ "$mode" == "base" ] && echo "$name"
        [ "$mode" == "ext" ] && echo ""
        return 0
    fi

    # Prüfung, ob überhaupt ein Punkt enthalten ist
    #if [ "${name%.*}" == "$name" ]; then
    #    # Kein . enthalten → also auch keine Fileext
    #    echo ""
    #    return
    #fi

                            #echo "${name%%.*}"  #  example.a.b.c.d  →  example
    [ "$mode" == "base" ] && echo "${name%.*}"   #  example.a.b.c.d  →  example.a.b.c
                            #echo "${name#*.}"   #  example.a.b.c.d  →  a.b.c.d
    [ "$mode" == "ext" ]  && echo "${name##*.}"  #  example.a.b.c.d  →  d
    return 0
}

function GetFileBase {
    GetFileBaseExt "$1" base
}

function GetFileExt {
    GetFileBaseExt "$1" ext
}

function Test_GetFileBaseExt {
    Test_Check "$(GetFileExt "verzeichnis  /example.a")"       "a"
    Test_Check "$(GetFileExt "verzeichnis  /example.a.b.c.d")" "d"
    Test_Check "$(GetFileExt "verzeichnis  /example.")"        ""
    Test_Check "$(GetFileExt "verzeichnis  /example")"         ""

    Test_Check "$(GetFileExt "")"              ""
    Test_Check "$(GetFileExt ".")"             ""
    Test_Check "$(GetFileExt "..")"            ""
    Test_Check "$(GetFileExt "...")"           ""
    Test_Check "$(GetFileExt "/x.y.z./...")"   ""
    Test_Check "$(GetFileExt "/x.y.z./...a")"  ""

    Test_Check "$(GetFileExt "Basename.ext with space")"  "ext with space"

    Test_Check "$(GetFileExt ".project.bla")"  "bla"
    Test_Check "$(GetFileExt ".project")"      ""
    Test_Check "$(GetFileExt " .project")"     "project"


    Test_Check "$(GetFileBase "verzeichnis  /example.a")"       "example"
    Test_Check "$(GetFileBase "verzeichnis  /example.a.b.c.d")" "example.a.b.c"
    Test_Check "$(GetFileBase "verzeichnis  /example.")"        "example"
    Test_Check "$(GetFileBase "verzeichnis  /example")"         "example"

    Test_Check "$(GetFileBase "")"              ""
    Test_Check "$(GetFileBase ".")"             "."
    Test_Check "$(GetFileBase "..")"            ".."
    Test_Check "$(GetFileBase "...")"           "..."
    Test_Check "$(GetFileBase "/x.y.z./...")"   "..."
    Test_Check "$(GetFileBase "/x.y.z./...a")"  "...a"

    Test_Check "$(GetFileBase "Basename.ext with space")"  "Basename"

    Test_Check "$(GetFileBase ".project.bla")"  ".project"
    Test_Check "$(GetFileBase ".project")"      ".project"
    Test_Check "$(GetFileBase " .project")"     " "
}
#Test_GetFileBaseExt


########################################################################################################################
#   _____ _                         _____            _    _   _
#  | ____(_) __ _  ___ _ __   ___  |  ___|   _ _ __ | | _| |_(_) ___  _ __   ___ _ __
#  |  _| | |/ _` |/ _ \ '_ \ / _ \ | |_ | | | | '_ \| |/ / __| |/ _ \| '_ \ / _ \ '_ \
#  | |___| | (_| |  __/ | | |  __/ |  _|| |_| | | | |   <| |_| | (_) | | | |  __/ | | |
#  |_____|_|\__, |\___|_| |_|\___| |_|   \__,_|_| |_|_|\_\\__|_|\___/|_| |_|\___|_| |_|
#           |___/
########################################################################################################################


########################################################################################################################
# Prüfung des Header Kommentars
#-----------------------------------------------------------------------------------------------------------------------
# \in  filename  Dateiname
# \in  linenr    Zeilnummer
# \in  linestr   Zeile (String)
#-----------------------------------------------------------------------------------------------------------------------
# C Sourcen nach dem Schema:
#     /***********************************************************************************************************************
#       Template
#     ------------------------------------------------------------------------------------------------------------------------
#       \project    VISTRA-I LED Anzeigetafel der EEO GmbH
#       \file       Template.c
#       \creation   2015-02-15, Joe Merten, JME Engineering Berlin
#     ------------------------------------------------------------------------------------------------------------------------
#       Optional weitere Beschreibung
#     ***********************************************************************************************************************/
#
# Shellskripte 6 Makefiles nach dem Schema:
#     ########################################################################################################################
#     # Sourcen untersuchen auf Korrektheit der Doxygen Kommentare
#     #-----------------------------------------------------------------------------------------------------------------------
#     # \project    Multithreaded C++ Framework
#     # \file       Doxycheck.sh
#     # \creation   2015-02-26, Joe Merten
#     #-----------------------------------------------------------------------------------------------------------------------
#     # Optional weitere Beschreibung
#     ########################################################################################################################
#
########################################################################################################################

DOXY_SOURCE_BEG_LINE='/***********************************************************************************************************************'
DOXY_SOURCE_SEP_LINE='------------------------------------------------------------------------------------------------------------------------'
DOXY_SOURCE_END_LINE='***********************************************************************************************************************/'
DOXY_BASH_BEG_LINE='########################################################################################################################'
DOXY_BASH_SEP_LINE='#-----------------------------------------------------------------------------------------------------------------------'
DOXY_BASH_END_LINE='########################################################################################################################'

function checkHeaderLine {
    local filename="$1"
    local linenr="$2"
    local linestr="$3"
    case "$linenr" in
        1) if [ "$linestr" != "$DOXY_SOURCE_BEG_LINE" ]; then
               Warning "$filename:$linenr: \"$linestr\""
           fi
        ;;
        3) if [ "$linestr" != "$DOXY_SOURCE_SEP_LINE" ]; then
               Warning "$filename:$linenr: \"$linestr\""
           fi
        ;;
    esac
}

########################################################################################################################
# Behandlung von genau einer Datei
########################################################################################################################
function DoFile {
    local filename="$1"
    local name="$(basename "$filename")"
    local ext="$(GetFileExt "$filename")"
    local linenr="0"

    while IFS= read -r line || [[ -n "$line" ]]; do
        let 'linenr++' ||:
        checkHeaderLine "$filename" "$linenr" "$line"
        [ "$linenr" == "10" ] && break
    done < "$filename"

    return 0
}

########################################################################################################################
# Schleife über alle zu behandelnden Dateien
########################################################################################################################
function DoAllFiles {
    Trace "Collecting Files"

    # Umwandlung der FILE_PATTERNS in einen für find passenden Regular Expression
    local re=""
    for pat in "${FILE_PATTERNS[@]}"; do
      [ "$re" != "" ] && re+='|'
      re+="$pat"
    done
    re="($re)"
    #Trace "Find RE = \"$re\""

    # Etwas Aufwand um auch mit Leerzeichen in Dateinamen umgehen zu können
    local files=()
    local i="0"
    # Erst mal alle Files einsammeln
    while IFS= read -r -d $'\0' file; do
        files[i++]="$file"
    done < <(find "${DIRS[@]}" -type f -regextype posix-egrep -regex "${re}" -print0)

    Trace "Found ${#files[@]} Files"

    for file in "${files[@]}"; do
        DoFile "$file"
    done
}


########################################################################################################################
#   _   _ _ _  __
#  | | | (_) |/ _| ___
#  | |_| | | | |_ / _ \
#  |  _  | | |  _|  __/
#  |_| |_|_|_|_|  \___|
########################################################################################################################

########################################################################################################################
# Hilfe
########################################################################################################################
function ShowHelp {
    echo "${AQUA}Doxycheck${TEAL}, Joe Merten 2015"
    echo "usage: $0 [options] ..."
    echo "Available options:"
    echo "  nocolor       - Dont use Ansi VT100 colors"
    #echo "  -m            - Modify files"
    #echo "  -e            - List file extentions"
    echo -n ${NORMAL}
}


########################################################################################################################
#   ____                                _
#  |  _ \ __ _ _ __ __ _ _ __ ___   ___| |_ ___ _ __
#  | |_) / _` | '__/ _` | '_ ` _ \ / _ \ __/ _ \ '__|
#  |  __/ (_| | | | (_| | | | | | |  __/ ||  __/ |
#  |_|   \__,_|_|  \__,_|_| |_| |_|\___|\__\___|_|
########################################################################################################################

########################################################################################################################
# Auswertung der Kommandozeilenparameter
########################################################################################################################
while (("$#")); do
    if [ "$1" == "?" ] || [ "$1" == "-?" ] || [ "$1" == "-h" ] || [ "$1" == "-help" ] || [ "$1" == "--help" ]; then
        ShowHelp
        exit 0
    elif [ "$1" == "nocolor" ]; then
        NoColor
#   elif [ "$1" == "-m" ] || [ "$1" == "--modify" ]; then
#       MODIFY="true"
    else
        DIRS+=("$1")
    fi
    shift
done

########################################################################################################################
#   __  __       _
#  |  \/  | __ _(_)_ __
#  | |\/| |/ _` | | '_ \
#  | |  | | (_| | | | | |
#  |_|  |_|\__,_|_|_| |_|
########################################################################################################################

########################################################################################################################
# Main...
########################################################################################################################

# Wenn kein Verzeichnis angegeben, dann defaulten wir auf "."
[ "${#DIRS[@]}" == "0" ] && DIRS+=('.')

# Meine FilePatterns sind Regular Expressions (wg. find)
FILE_PATTERNS+=('.*\.h')
FILE_PATTERNS+=('.*\.c')
FILE_PATTERNS+=('.*\.hxx')
FILE_PATTERNS+=('.*\.cxx')
FILE_PATTERNS+=('.*\.hpp')
FILE_PATTERNS+=('.*\.cpp')

#FILE_PATTERNS+=('.*\.s')
#FILE_PATTERNS+=('.*\.S')
#FILE_PATTERNS+=('.*\.ld')
#FILE_PATTERNS+=('.*\.lds')

#FILE_PATTERNS+=('.*Makefile')
#FILE_PATTERNS+=('.*Makefile\..*') # z.B. für "Makefile.posix"
#FILE_PATTERNS+=('.*\.mk')
#FILE_PATTERNS+=('.*\.sh')
#FILE_PATTERNS+=('.*\.bsh')

# zus. für Android / Java
FILE_PATTERNS+=('.*\.java')
#FILE_PATTERNS+=('.*\.prefs')
#FILE_PATTERNS+=('.*\.properties')
#FILE_PATTERNS+=('.*\.xml')
#FILE_PATTERNS+=('.*\.classpath')
#FILE_PATTERNS+=('.*\.project')

DoAllFiles
