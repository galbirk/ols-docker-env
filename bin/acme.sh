#!/usr/bin/env bash
EMAIL=''
NO_EMAIL=''
DOMAIN=''
INSTALL=''
UNINSTALL=''
TYPE=0
CONT_NAME='ols-deployment-598665445c-bxjs6'
ACME_SRC='https://raw.githubusercontent.com/Neilpang/acme.sh/master/acme.sh'
EPACE='        '

echow(){
    FLAG=${1}
    shift
    echo -e "\033[1m${EPACE}${FLAG}\033[0m${@}"
}

help_message(){
    case ${1} in
    "1")    
        echo 'You will need to install acme script at the first time.'
        echo 'Please run acme.sh --install --email example@example.com'
        ;;
    "2")
        echo -e "\033[1mOPTIONS\033[0m" 
        echow '-D, --domain [DOMAIN_NAME]'         
        echo "${EPACE}${EPACE}Example: acme.sh --domain example.com"
        echo "${EPACE}${EPACE}will auto detect and apply for both example.com and www.example.com domains."
        echow '-H, --help'
        echo "${EPACE}${EPACE}Display help and exit."
        echo -e "\033[1m   Only for the First time\033[0m"
        echow '--install --email [EMAIL_ADDR]'
        echo "${EPACE}${EPACE}Will install ACME with the Email provided"       
        exit 0
        ;;
    "3")
        echo 'Please run acme.sh --domain [DOMAIN_NAME] to apply certificate'
        exit 0
        ;;
    esac
}

check_input(){
    if [ -z "${1}" ]; then
        help_message 2
    fi
}

domain_filter(){
    if [ -z "${1}" ]; then
        help_message 3
    fi
    DOMAIN="${1}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#ftp://}"
    DOMAIN="${DOMAIN#scp://}"
    DOMAIN="${DOMAIN#scp://}"
    DOMAIN="${DOMAIN#sftp://}"
    DOMAIN=${DOMAIN%%/*}
}

email_filter(){
    CKREG="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"
    if [[ "${1}" =~ ${CKREG} ]] ; then
        echo -e "[O] The E-mail \033[32m${1}\033[0m is valid."
    else
        echo -e "[X] The E-mail \e[31m${1}\e[39m is invalid"
        exit 1
    fi
}

cert_hook(){
    echo '[Start] Adding ACME hook'
    kubectl exec -it ${CONT_NAME} -- su -s /bin/bash -c "certhookctl.sh"
    echo '[End] Adding ACME hook'
}

www_domain(){
    CHECK_WWW=$(echo ${1} | cut -c1-4)
    if [[ ${CHECK_WWW} == www. ]] ; then
        DOMAIN=$(echo ${1} | cut -c 5-)
    else
        DOMAIN=${1}    
    fi
    WWW_DOMAIN="www.${DOMAIN}"
}

domain_verify(){
    curl -Is http://${DOMAIN}/ | grep -i LiteSpeed > /dev/null 2>&1
    if [ ${?} = 0 ]; then
        echo -e "[O] The domain name \033[32m${DOMAIN}\033[0m is accessible."
        TYPE=1
        curl -Is http://${WWW_DOMAIN}/ | grep -i LiteSpeed > /dev/null 2>&1
        if [ ${?} = 0 ]; then
            echo -e "[O] The domain name \033[32m${WWW_DOMAIN}\033[0m is accessible."
            TYPE=2
        else
            echo -e "[!] The domain name ${WWW_DOMAIN} is inaccessible." 
        fi
    else
        echo -e "[X] The domain name \e[31m${DOMAIN}\e[39m is inaccessible, please verify."
        exit 1    
    fi
}

install_acme(){
    echo '[Start] Install ACME'
    if [ "${1}" = 'true' ]; then
        kubectl exec -it ols-deployment-598665445c-bxjs6 -- su -c "cd; wget ${ACME_SRC}; chmod 755 acme.sh; \
        ./acme.sh --install --cert-home  ~/.acme.sh/certs; \
        rm ~/acme.sh"
    elif [ "${2}" != '' ]; then
        email_filter "${2}"
        kubectl exec -it ols-deployment-598665445c-bxjs6 -- su -c "cd; wget ${ACME_SRC}; chmod 755 acme.sh; \
        ./acme.sh --install --cert-home  ~/.acme.sh/certs --accountemail  ${2}; \
        rm ~/acme.sh"
    else
        help_message 1
        exit 1
    fi
    echo '[End] Install ACME'
}

uninstall_acme(){
    echo '[Start] Uninstall ACME'
    kubectl exec -it ${CONT_NAME} -- su -c "~/.acme.sh/acme.sh --uninstall"
    echo '[End] Uninstall ACME'
    exit 0
}    

check_acme(){
    echo '[Start] Checking ACME'
    kubectl exec -it ${CONT_NAME} -- su -c "test -f /root/.acme.sh/acme.sh"
    if [ ${?} != 0 ]; then
        install_acme "${NO_EMAIL}" "${EMAIL}"
        cert_hook
        help_message 3
    fi
    echo '[End] Checking ACME'
}

lsws_restart(){
    kubectl exec -it ${CONT_NAME} -- su -c '/usr/local/lsws/bin/lswsctrl restart >/dev/null'
}

doc_root_verify(){
    if [ "${DOC_ROOT}" = '' ]; then
        DOC_PATH="/var/www/vhosts/${1}/html"
    else
        DOC_PATH="${DOC_ROOT}"    
    fi
    kubectl exec -it ${CONT_NAME} -- su -c "[ -e ${DOC_PATH} ]"
    if [ ${?} -eq 0 ]; then
        echo -e "[O] The document root folder \033[32m${DOC_PATH}\033[0m does exist."
    else
        echo -e "[X] The document root folder \e[31m${DOC_PATH}\e[39m does not exist!"
        exit 1
    fi
}

install_cert(){
    echo '[Start] Apply Lets Encrypt Certificate'
    if [ ${TYPE} = 1 ]; then
        kubectl exec -it ${CONT_NAME} -- su -c "/root/.acme.sh/acme.sh --issue -d ${1} -w ${DOC_PATH}"
    elif [ ${TYPE} = 2 ]; then
        kubectl exec -it ${CONT_NAME} -- su -c "/root/.acme.sh/acme.sh --issue -d ${1} -d www.${1} -w ${DOC_PATH}"
    else
        echo 'unknown Type!'
        exit 2
    fi
    echo '[End] Apply Lets Encrypt Certificate'
}

main(){
    check_acme
    domain_filter ${DOMAIN}
    www_domain ${DOMAIN}
    domain_verify
    doc_root_verify ${DOMAIN}
    install_cert ${DOMAIN}
    lsws_restart
}

check_input ${1}
while [ ! -z "${1}" ]; do
    case ${1} in
        -[hH] | -help | --help)
            help_message 2
            ;;
        -[dD] | -domain | --domain) shift
            check_input "${1}"
            DOMAIN="${1}"
            ;;
        -[iI] | --install ) 
            INSTALL=true
            ;;
        -[uU] | --uninstall )
            UNINSTALL=true
            uninstall_acme
            ;;            
        -[eE] | --email ) shift
            check_input "${1}"
            EMAIL="${1}"
            ;;           
        *) 
            help_message 2
            ;;              
    esac
    shift
done

main