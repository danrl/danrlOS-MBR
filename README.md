# danrlOS-MBR

x86-bootloader


## About

A x86-bootloader for danrlOS using Disk Address Packets for boot-media access.
BIOS Interrupt 0x13 with register AH set to 0x42 allows extended reading of sectors from a drive. This method allows a bootloader to load data from a drive without calculating head and track numbers. Moreover, it is possible to boot a kernel that resides at the end of a large drive. Unfortunately, most bootloaders still use the old and limited method Interrupt 0x13 with AH set to 0x02.


## Author

Written by Dan Luedtke <mail@danrl.de>.


## License

	danrlOS-MBR - x86-bootloader
	Copyright (C) 2011  Dan Luedtke <mail@danrl.de>

	This program is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 3 of the License, or
	(at your option) any later version.

	This program is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program.  If not, see <http://www.gnu.org/licenses/>.
