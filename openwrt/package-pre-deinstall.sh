#!/bin/sh
/etc/init.d/openflux stop
/usr/libexec/openflux-network cleanup
/etc/init.d/openflux disable
