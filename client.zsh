#!/bin/zsh
IFS=" "
SOCKFD=$1

user=
nick=
realname=
hostname=
mode=

integer fd
zmodload zsh/system zsh/net/socket zsh/mapfile zsh/sched

function parse() {
    read command rest
    IFS=: read params last <<< "$rest"

    params=(${=params})
    if [ -n "$last" ]; then
	params+=$last
    fi

    command=$command:u
    doCommand $command $params
}

function doCommand() {
    case $command in
	USER)
	    setUser $params
	    ;;
	NICK)
	    changeNick $params
	    ;;
	PRIVMSG)
	    sendPRIVMSG $params
	    ;;
	NOTICE)
	    sendNOTICE $params
	    ;;
	WHOIS)
	    doWhois $params
	    ;;
	PONG)
	    resetWD
	    ;;
	PING)
	    echo :$HOST PONG :$params
	    ;;
	QUIT)
	    quit $params
	    ;;
	*)
	    echo :$HOST 421 $command :Unknown command $command
	    ;;
    esac
}

function doInit() {
    mkdir "clients/$$"
    mkfifo "clients/$$/sock"

    exec {fd}<>"clients/$$/sock"
    while read line; do echo $line >&$SOCKFD; done <&$fd &
}

function resetWD() {
    pingcookie=$RANDOM
    echo :$HOST PING :$pingcookie
    sched +300 quit "Ping timeout"
}

function doWhois() {
    _nick=$1

    if [ -z "$_nick" ]; then
        echo :$HOST 431 :No nickname given
        return 1
    fi

    if [ ! "$_nick" '=~' '^[[:alpha:]][[:alnum:]\-\[-\`_-}]{0,8}$' ]; then
        echo :$HOST 432 $_nick :Erroneous nickname
        return 1
    fi

    _realname=$mapfile["nicks/$_nick/realname"]
    _user=$mapfile["nicks/$_nick/user"]
    _hostname=$mapfile["nicks/$_nick/hostname"]
    #realname=mapfile["nicks/$_nick/realname"]

    echo :$HOST 311 $nick $_nick $_user $_hostname :$realname
    echo :$HOST 318 $nick :End of WHOIS list
}

function sendPRIVMSG() {
    targets=$1
    if [ -z "$targets" ]; then
	echo ":$HOST 411 :No recipient given PRIVMSG"
	return 255
    fi
    MESSAGE=$2

    if [ -z "$MESSAGE" ]; then
	echo ":$HOST 412 :No text to send"
	return 255
    fi
    IFS=, read -rA targets <<< "$targets"
    MESSAGE=$2

    for target in $targets; do
	if [[ -h "target/$target" ]]; then
	    echo ":$nick!$UPREFIX PRIVMSG $target :$MESSAGE" > "target/$target"
	else
	    echo ":$HOST 401 $target :No such nick/channel" >&$SOCKFD
	fi
    done
}

function setUser() {
    _user=$1
    _mode=$2
    _hostname=$3
    _realname=$4

    if [[ -z "$_mode" || -z "$_realname" ]]; then
	echo :$HOST 461 USER :Not enough parameters
    fi


    if [ -n "$user" ]; then
	echo ":$HOST 462 :Unauthorized command (already registered)"
	return 255
    fi

    user=$_user
    mode=$_mode
    hostname=$_hostname
    realname=$_realname

    cat <<< "$user" > "clients/$$/user"
    cat <<< "$realname" > "clients/$$/realname"
    cat <<< "$mode" > "clients/$$/mode"
    cat <<< "$hostname" > "clients/$$/hostname"

    if [ -n "$nick" ]; then
      welcome
    fi
}

function changeNick() {
    _nick=$1

    if [ -z "$_nick" ]; then
	echo :$HOST 431 :No nickname given
	return 1
    fi

    if [ ! "$_nick" '=~' '^[[:alpha:]][[:alnum:]\-\[-\`_-}]{0,8}$' ]; then
	echo :$HOST 432 $_nick :Erroneous nickname
	return 1
    fi

    if [ -d "nicks/$_nick" ]; then
	echo :$HOST 433 $_nick :Nickname is already in use
	return
    fi

    touch "lock/nicks/$_nick"
    if zsystem flock -t 1 "lock/nicks/$_nick"; then
	:
    else
	echo :$HOST 433 $nick :Nickname is already in use
    fi

    if [ -n "$nick" ]; then
	rm "lock/nicks/$nick"
    fi

    ln -s "../clients/$$" "nicks/$_nick"
    ln -s "../clients/$$/sock" "target/$_nick"


    if [ -n "$nick" ]; then
#	echo :$nick!$UPREFIX NICK $nick > nicks/$nick/channels/*
	echo :$nick!$user NICK $_nick

	rm target/$nick
	rm nicks/$nick
	rm lock/nicks/$nick
    fi

    nick=$_nick

    if [ -n "$user" ]; then
	welcome
    fi
}

function welcome() {
    echo :$HOST 001 $nick :Welcome to the Internet Relay Network $nick!$UPREFIX
    echo :$HOST 002 $nick :Your host is $HOST, running version -1
    echo :$HOST 003 $nick :This server was created $CREATED
    echo :$HOST 004 $nick :$HOST -1 i l
}

doInit

while read line
do echo $line | sed 's/^:\S* //' | tr -d '\r' | parse >& $1; done <& $1

exec {SOCKFD}>&-