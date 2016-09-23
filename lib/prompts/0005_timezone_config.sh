#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License version 2 as
#  published by the Free Software Foundation.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#  See the GNU General Public License for more details.

# Timezone related prompts

timezone_config()
{
	local tmpfile=$(mktemp)
	tzinfo="/usr/share/zoneinfo"
	while [ ! -f "$tzinfo" ]; do
		if [ "$tzinfo" != "/usr/share/zoneinfo" ]; then
			menuitems=".. .."
		else
			menuitems=""
		fi
		filecount=0
		for i in `ls -1 ${tzinfo}`; do
			menuitems="$menuitems $i $i"
			let filecount++
		done
		dialog --no-tags --menu "Select your time zone:" \
			$(expr $filecount + 7) 100 $filecount $menuitems 2>$tmpfile
		dialog_res=$(cat $tmpfile)
		if [ "$dialog_res" == ".." ]; then
			tzinfo=`dirname $tzinfo`
		elif [ -n "$dialog_res" ]; then
			tzinfo="$tzinfo/$dialog_res"
		fi
	done
	tzinfo=${tzinfo:20}
	cat <<EOF >> ${tmppuppet}
exec { 'set_localtime':
	command => "/bin/ln -sf /usr/share/zoneinfo/${tzinfo} /etc/localtime",
}
file { 'timezone':
path => "/etc/timezone",
content => "${tzinfo}",
}

EOF


	rm $tmpfile
}

