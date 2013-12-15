## Scope ##

This is a very simple Vera plugin for FHT thermostats connected to FHEM. It is assumed that you already have FHEM running on your local network and have set up your FHT devices. 

## Features ##

It only supports the FHT thermostats and provides the following functions:

* Poll FHEM to get actual and desired temperatures for the FHT and update the corresponding Vera device
* Allow setting of the desired temperature on the FHT device from Vera

## Usage ##

I didn't follow the model of shared master + child devices for this plugin (room for improvement there). This means you need to create one instance for each thermostat. Give each an IP address (of FHEM) and give the FHEM id as the alt id in Vera.

## Limitations ##

This is a pretty basic plugin. Would be nice to do something with the holiday mode but I never got round to it.

It could be redesigned with a master device that connects to FHEM and creates child devices in Vera for all configured FHEM devices. I don't really have any compelling reason to spend the time on this at the moment, however. 

Usage of FHEM in the middle at all is a bit of a hack. Would be better to communicate with FHT devices direct. Maybe using RFXtrx?

## Credits ##

Heavily based on Hugh Evans' "MiOS Plugin for Radio Thermostat Corporation of America, Inc. Wi-Fi Thermostats" (Copyright 2012)

## License ##

Copyright © 2013 Chris Birkinshaw and others

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/