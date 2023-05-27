#!/bin/bash

printGood() {
        echo -e "[\e[32m+\e[0m] $1"
}

printWorking() {
        echo -e "[\e[33m~\e[0m] $1"
}

printBad() {
        echo -e "[\e[31m!\e[0m] $1"
}

if [[ "$EUID" -ne 0 ]]; then
    printBad "The script must be run as root."
    printBad "Usage: sudo ./ssh-webhook-setup.sh"
    exit 1
fi

if [ $(getenforce) = "Enforcing" ] ; then
    printWorking "SELinux enabled, checking NIS status..."
        if [ $(sestatus -b | grep nis_enabled | awk '{print $2}') = "off" ] ; then
            if setsebool -P nis_enabled 1 ; then
                printGood "NIS enabled"
            else
                printBad "Failed to enabled NIS"
                exit 1
            fi
        else
            printGood "NIS already enabled"
        fi
fi

printWorking "Creating /sbin/sshd-login"
if touch /sbin/sshd-login ; then
    printGood "/sbin/sshd-login sucessfully created"
else
    printBad "Failed to create /sbin/sshd-login"
    exit 1
fi
printWorking "Writing script to /sbin/sshd-login"
cat > /sbin/sshd-login<< EOF
#!/bin/bash
# add to /sbin/ and make executable
# edit /etc/pam.d/sshd and add:
# session   optional   pam_exec.so /sbin/sshd-login
# to bottom of the file

WEBHOOK_URL="CHANGE ME"
DISCORDUSER="CHANGE ME"

# Capture only open and close sessions.
case "\$PAM_TYPE" in
    open_session)
        PAYLOAD=" { \"content\": \"\$DISCORDUSER: User \\\`\$PAM_USER\\\` logged in to \\\`\$HOSTNAME\\\` (remote host: \$PAM_RHOST).\" }"
        ;;
    close_session)
        PAYLOAD=" { \"content\": \"\$DISCORDUSER: User \\\`\$PAM_USER\\\` logged out of \\\`\$HOSTNAME\\\` (remote host: \$PAM_RHOST).\" }"
        ;;
esac

# If payload exists fire webhook
if [ -n "\$PAYLOAD" ] ; then
    curl -X POST -H 'Content-Type: application/json' -d "\$PAYLOAD" "\$WEBHOOK_URL"
fi
EOF
printGood "Finished writing script to file"
printWorking "Modifying file permissions"

if ! chmod +x /sbin/sshd-login ; then
    printBad "Failed to make /sbin/sshd-login executable"
    exit 1
fi
if ! chown root:root /sbin/sshd-login ; then
    printBad "Failed to set root as owner of /bin/sshd-login"
    exit 1
fi

if ! echo -e 'session optional pam_exec.so type=close_session log=/tmp/test_pam.txt /sbin/sshd-login\nsession optional pam_exec.so type=open_session log=/tmp/test_pam.txt /sbin/sshd-login' >> /etc/pam.d/sshd ; then
    printBad "Failed to append PAM instructions to /etc/pam.d/sshd"
    exit 1
fi
printWorking "Restarting sshd service"
systemctl restart sshd
printGood "Installation complete!"