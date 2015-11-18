file { "/etc/hostname":
    ensure => present,
    owner => root,
    group => root,
    mode => 644,
    content => "cube-essential\n",
}

group { "guest":
    name => "guest",
    ensure => present,
}

user { "guest":
    ensure => present,
    gid => "guest",
    groups => ["users"],
    membership => minimum,
    shell => "/bin/bash",
    require => [Group["guest"]],
    password => '$6$Wc94sj12$WISqg0O5gOTTER3rDU9UiP.UEDZDhHqkkF.zOgKp/cEAqfUtdYGRP49e9.Tr6qgpIJAIZRZI9sfcjLvMPsAZv1',
}
