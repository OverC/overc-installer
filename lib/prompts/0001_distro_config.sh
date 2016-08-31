#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

# Distribution related prompts

distro_config()
{
	local tmpfile=$(mktemp)
	dialog --no-cancel --inputbox "Distribution name:" 8 40 "OverC" 2>$tmpfile
	dialog_res=$(cat $tmpfile)
	if [ -n "${dialog_res}" ]; then
		echo "DISTRIBUTION=\"${dialog_res}\"" >> ${tmpconf}
	else
		echo "DISTRIBUTION=\"OverC\"" >> ${tmpconf}
	fi
	rm $tmpfile
}

