#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

# User related prompts

user_config()
{
	local tmpfile=$(mktemp)
	# Add new user
	dialog --no-cancel --inputbox "Create new user(leave blank if not wanted):" 8 60 2>$tmpfile
	username=$(cat $tmpfile)
	if [ -n "$username" ]; then
		passwd1="" passwd2="" passwdprompt="Please input password:"
		while [ -z "$passwd1" ] || [ -z "$passwd2" ] || [ "$passwd1" != "$passwd2" ]; do
			dialog --no-cancel --inputbox "$passwdprompt" 8 40 2>$tmpfile
			passwd1=$(cat $tmpfile)
			dialog --no-cancel --inputbox "Please confirm password:" 8 40 2>$tmpfile
			passwd2=$(cat $tmpfile)
			passwdprompt="Password mismatch! Please re-input password:"
		done
		cryptpasswd=$(python -c "import crypt; print crypt.crypt(\"$passwd1\", \"\$6\$\")")
	fi

	echo "INITIAL_USER=\"${username}\"" >> ${tmpconf}
	echo "INITIAL_PASSWD=${cryptpasswd}" >> ${tmpconf}
	rm $tmpfile
}
