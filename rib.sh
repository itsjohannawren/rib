#!/bin/bash

#aptitude install binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools

# =============================================================================
# BEGIN LOGGING AND OUTPUT FUNCTIONS

# ANSI Color Base
__STATUS_ANSI_S="\0033["
# ANSI Color Codes
__STATUS_ANSI_RESET="0"
__STATUS_ANSI_BOLD_ON="1"
__STATUS_ANSI_F_RED="31"
__STATUS_ANSI_F_GREEN="32"
__STATUS_ANSI_F_YELLOW="33"
__STATUS_ANSI_F_BLUE="34"

__STATUS_INDENT=""

eindent() {
	__STATUS_INDENT="${__STATUS_INDENT}  "
}

eoutdent() {
	__STATUS_INDENT="$(echo -ne "${__STATUS_INDENT}" | sed -r -e "s/^  //")"
}

ebegin() {
	echo -e "${__STATUS_ANSI_S}${__STATUS_ANSI_F_GREEN};${__STATUS_ANSI_BOLD_ON}m${__STATUS_INDENT} * ${__STATUS_ANSI_S}${__STATUS_ANSI_RESET}m$* ..." 1>&2
	eindent
}

eend() {
	if [ 0 -eq "${1}" ]; then
		echo -e "${__STATUS_ANSI_S}1A${__STATUS_ANSI_S}1000C${__STATUS_ANSI_S}6D${__STATUS_ANSI_S}${__STATUS_ANSI_F_BLUE}m[ ${__STATUS_ANSI_S}${__STATUS_ANSI_F_GREEN};${__STATUS_ANSI_BOLD_ON}mok ${__STATUS_ANSI_S}${__STATUS_ANSI_F_BLUE}m]${__STATUS_ANSI_S}${__STATUS_ANSI_RESET}m"
	else
		echo -e "${__STATUS_ANSI_S}1A${__STATUS_ANSI_S}1000C${__STATUS_ANSI_S}6D${__STATUS_ANSI_S}${__STATUS_ANSI_F_BLUE}m[ ${__STATUS_ANSI_S}${__STATUS_ANSI_F_RED};${__STATUS_ANSI_BOLD_ON}m!! ${__STATUS_ANSI_S}${__STATUS_ANSI_F_BLUE}m]${__STATUS_ANSI_S}${__STATUS_ANSI_RESET}m"
		if [ -n "${2}" ]; then
			efatal "Quiting"
		fi
	fi
	eoutdent
}

einfo() {
	echo -e "${__STATUS_ANSI_S}${__STATUS_ANSI_F_GREEN};${__STATUS_ANSI_BOLD_ON}m${__STATUS_INDENT} * ${__STATUS_ANSI_S}${__STATUS_ANSI_RESET}m$*" 1>&2
}

ewarn() {
	echo -e "\0007\0007${__STATUS_ANSI_S}${__STATUS_ANSI_F_YELLOW};${__STATUS_ANSI_BOLD_ON}m${__STATUS_INDENT} # ${__STATUS_ANSI_S}${__STATUS_ANSI_RESET}m$*" 1>&2
	sleep 1
}

eerror() {
	echo -e "${__STATUS_ANSI_S}${__STATUS_ANSI_F_RED};${__STATUS_ANSI_BOLD_ON}m${__STATUS_INDENT} ! ${__STATUS_ANSI_S}${__STATUS_ANSI_RESET}m$*" 1>&2
}

efatal() {
	echo -e "${__STATUS_ANSI_S}${__STATUS_ANSI_F_RED};${__STATUS_ANSI_BOLD_ON}m${__STATUS_INDENT} ! ${__STATUS_ANSI_S}${__STATUS_ANSI_RESET}m$*" 1>&2
	exit 1
}
# END LOGGING AND OUTPUT FUNCTIONS
# =============================================================================

DEBIAN_MIRROR="http://http.us.debian.org/debian"
DEBIAN_RELEASE="wheezy"

IMAGE_SIZE="1024" #MB
BOOT_PARTITION_SIZE="64M"
IMAGE_SHRINK="yes"
IMAGE_ROOT_EXTRA="20M"

BUILD_IMAGE="${1}"
BUILD_DIR="$(pwd)"
BUILD_BASE_DIR="${BUILD_DIR}/base"
BUILD_ROOT_DIR="${BUILD_DIR}/build"
BUILD_BOOT_DIR="${BUILD_ROOT_DIR}/boot"

# =============================================================================

parseSize() {
	__UNIT="$(sed -e 's/^[0-9][0-9]*//' <<< "${1}")"
	__SIZE="$(sed -e 's/[a-zA-Z]$//' <<< "${1}")"
	if [ -z "${__UNIT}" ]; then
		__UNIT="B"
	fi
	case "${__UNIT}" in
		b|B)
			__SIZE="$((__SIZE * 1))"
			;;
		k|K)
			__SIZE="$((__SIZE * 1024))"
			;;
		m|M)
			__SIZE="$((__SIZE * 1024 * 1024))"
			;;
		g|G)
			__SIZE="$((__SIZE * 1024 * 1024 * 1024))"
			;;
		t|T)
			__SIZE="$((__SIZE * 1024 * 1024 * 1024 * 1024))"
			;;
		*)
			ewarn "Cannot determine length of root data"
			return 1
			;;
	esac

	echo "${__SIZE}"
	return 0
}

humanSize() {
	awk '
		function human(x) {
			s=" KMGTEPYZ";
			while (x>=1024 && length(s)>1) {
				x/=1024;
				s=substr(s,2);
			}
			return sprintf ("%8.2f %s", x, substr(s,1,1));
		}
		{gsub(/^[0-9]+/, human($1)); print}' <<< "${1}" | head -n 1 | sed -e 's/\.00//' -e 's/ $//' -e 's/$/B/'
}

# =============================================================================

if [ -z "${DEBIAN_MIRROR_LOCAL}" ]; then
	DEBIAN_MIRROR_LOCAL=${DEBIAN_MIRROR}
fi

if [ "${EUID}" -ne "0" ]; then
	efatal "This tool must be run as root" 1>&2
fi

if [ "${BUILD_IMAGE}" != "--chroot" ]; then
	if [ -n "${BUILD_IMAGE}" ] && ! [ -b "${BUILD_IMAGE}" ]; then
		efatal "${BUILD_IMAGE} is not a block device" 1>&2
	fi

	echo
	einfo "rib RPi Image Builder"
	echo

	einfo "Preparing image/blockdevice ..."
	eindent

	if [ -z "${BUILD_IMAGE}" ]; then
		einfo "No block device given, creating a image"
		eindent
		
		BUILD_IMAGE="${BUILD_DIR}/${DEBIAN_RELEASE}+rib+rpi-$(date +"%Y%m%d").img"

		ebegin "Creating blank image"
		dd if=/dev/zero "of=${BUILD_IMAGE}" bs=$((1024 * 1024)) "count=${IMAGE_SIZE}" &>/dev/null
		eend $? 1

		ebegin "Setting up loopback for image"
		IMAGE_DEVICE="$(losetup -f --show "${BUILD_IMAGE}")"
		eend $? 1

		eoutdent # No block device given, creating a image

	else
		einfo "Block device given, not making an image"

		ebegin "Clearing beginning of block device"
		dd if=/dev/zero "of=${BUILD_IMAGE}" bs=512 count=10 >/dev/null
		eend $? 1
	fi

	ebegin "Partitioning device"
	fdisk "${BUILD_IMAGE}" <<EOF &>/dev/null
n
p
1

+${BOOT_PARTITION_SIZE}
t
c
n
p
2


w
EOF
	eend $?

	if ! [ -b "${BUILD_IMAGE}" ]; then
		ebegin "Removing loopback for image"
		losetup -d "${IMAGE_DEVICE}"
		eend $? 1

		ebegin "Setting up loopbacks for partitions"
		IMAGE_DEVICE="$(kpartx -va "${BUILD_IMAGE}" | sed -E 's/.*(loop[0-9][0-9]*)p.*/\1/g' | head -n 1)"
		eend $? 1

		BUILD_BOOT_DEVICE="/dev/mapper/${IMAGE_DEVICE}p1"
		BUILD_ROOT_DEVICE="/dev/mapper/${IMAGE_DEVICE}p2"
		IMAGE_DEVICE="/dev/${IMAGE_DEVICE}"

	else
		if [ -b "${BUILD_IMAGE}1" ]; then
			einfo "Using DEV# notation for block device partitions"
			BUILD_BOOT_DEVICE="${BUILD_IMAGE}1"
			BUILD_ROOT_DEVICE="${BUILD_IMAGE}2"

		elif [ -b "${BUILD_IMAGE}p1" ]; then
			einfo "Using DEVp# notation for block device partitions"
			BUILD_BOOT_DEVICE="${BUILD_IMAGE}p1"
			BUILD_ROOT_DEVICE="${BUILD_IMAGE}p2"
		
		else
			efatal "Unknown partition scheme on block device"
		fi
	fi

	einfo "Formatting ..."
	eindent

	ebegin "boot"
	mkfs.vfat "${BUILD_BOOT_DEVICE}" &>/dev/null
	eend $? 1

	ebegin "root"
	mkfs.ext4 "${BUILD_ROOT_DEVICE}" &>/dev/null
	eend $? 1

	eoutdent # Formatting

	einfo "Mounting ..."
	eindent

	ebegin "Creating root directory"
	mkdir -p "${BUILD_ROOT_DIR}"
	eend $? 1

	ebegin "Mounting root partition"
	mount "${BUILD_ROOT_DEVICE}" "${BUILD_ROOT_DIR}"
	eend $? 1

	ebegin "Creating boot directory"
	mkdir -p "${BUILD_BOOT_DIR}"
	eend $? 1

	ebegin "Mounting boot partition"
	mount "${BUILD_BOOT_DEVICE}" "${BUILD_BOOT_DIR}"
	eend $? 1

	eoutdent # Mounting

	eoutdent # Preparing image/block device

	cd "${BUILD_ROOT_DIR}"

	einfo "Building ..."
	eindent

	ebegin "Bootstrapping stage 1"
	debootstrap --foreign --variant=minbase --arch armel "${DEBIAN_RELEASE}" "${BUILD_ROOT_DIR}" "${DEBIAN_MIRROR}" >/dev/null
	eend $? 1

	ebegin "Copying qemu-arm-static into image"
	cp /usr/bin/qemu-arm-static usr/bin/
	eend $? 1

	ebegin "Running stage 2"
	LANG="C" chroot . /debootstrap/debootstrap --second-stage &>/dev/null
	eend $? 1

	einfo "Preparing for stage 3"
	eindent

	ebegin "Clearing /boot"
	rm -rf boot/*
	eend $? 1

	cd "${BUILD_BASE_DIR}"
	ebegin "Copying base setup and configuration files"
	rsync -aHv * "${BUILD_ROOT_DIR}/" >/dev/null
	eend $? 1
	
	if [ -d "${BUILD_DIR}/overlay" ]; then
		cd "${BUILD_DIR}"
		ebegin "Copying overlay setup and configuration files"
		rsync -aHv overlay "${BUILD_ROOT_DIR}/" >/dev/null
		eend $? 1
	fi

	cd "${BUILD_ROOT_DIR}"

	ebegin "Copying self"
	cp -p "${BUILD_DIR}/rib.sh" ./
	eend $? 1

	eoutdent # Preparing for stage 3

	eoutdent # Building

	ebegin "Jumping to stage 3"
	LANG="C" chroot . /rib.sh --chroot
	eend $? 1

	cd "${BUILD_DIR}"

	einfo "Cleaning up"
	eindent

	PIDS="$(lsof -nnP | grep "${BUILD_ROOT_DIR}" | awk '{print $2}' | sort | uniq)"
	if [ -n "${PIDS}" ]; then
		einfo "Killing things that started"
		eindent

		for PID in ${PIDS}; do
			ebegin "${PID}: $(sed -e 's/\x00/ /g' -e 's/ $//' "/proc/${PID}/cmdline")"
			kill "${PID}" &>/dev/null
			eend $?
		done

		eoutdent # Killing things that started
	fi

	for FILE in usr/bin/qemu-arm-static debconf.set rib.sh overlay; do
		ebegin "/${FILE}"
		rm -rf "${BUILD_ROOT_DIR}/${FILE}" >/dev/null
		eend $?
	done

	eoutdent # Cleaning up

	cd "${BUILD_DIR}"

	einfo "Space Used"
	eindent

	einfo "Boot: $(df -k "${BUILD_BOOT_DEVICE}" | awk '/^\// {print $3}') KB"
	einfo "Root: $(df -k "${BUILD_ROOT_DEVICE}" | awk '/^\// {print $3}') KB"

	eoutdent # Space used

	einfo "Finalizing"
	eindent

	ebegin "Syncing"
	sync &>/dev/null && sleep 15
	eend $? 1

	ebegin "Unmounting boot partition"
	umount "${BUILD_BOOT_DEVICE}" >/dev/null
	eend $?

	ebegin "Unmount root partition"
	umount "${BUILD_ROOT_DEVICE}" >/dev/null
	eend $?

	if ! [ -b "${BUILD_IMAGE}" ]; then
		if [ "${IMAGE_SHRINK}" = "yes" ]; then
			einfo "Shrinking image ..."
			eindent

			ebegin "fsck'ing root filesystem"
			fsck -fy "${BUILD_ROOT_DEVICE}" &>/dev/null
			eend $? 1

			ebegin "Shrinking root filesystem"
			resize2fs -M "${BUILD_ROOT_DEVICE}" &>/dev/null
			eend $?

			ROOT_JOURNAL_SIZE="0B"
			ROOT_BLOCK_COUNT="0"
			ROOT_BLOCK_SIZE="0"
			eval "$(dumpe2fs "${BUILD_ROOT_DEVICE}" 2>/dev/null | awk '/^Journal size:/ {printf("ROOT_JOURNAL_SIZE=%s\n",$3);} /^Block count:/ {printf("ROOT_BLOCK_COUNT=%s\n",$3);} /^Block size:/ {printf("ROOT_BLOCK_SIZE=%s\n",$3);}')"

			ROOT_DATA_SIZE="$((ROOT_BLOCK_COUNT * ROOT_BLOCK_SIZE))"
			ROOT_JOURNAL_SIZE="$(parseSize "${ROOT_JOURNAL_SIZE}")"
			IMAGE_ROOT_EXTRA="$(parseSize "${IMAGE_ROOT_EXTRA}")"

			ROOT_SIZE="$((ROOT_DATA_SIZE + ROOT_JOURNAL_SIZE + IMAGE_ROOT_EXTRA))"

			einfo "Sizes"
			eindent

			einfo "Root (data):    $(humanSize "${ROOT_DATA_SIZE}")"
			einfo "Root (journal): $(humanSize "${ROOT_JOURNAL_SIZE}")"
			einfo "Root (extra):   $(humanSize "${IMAGE_ROOT_EXTRA}")"
			einfo "Root (total):   $(humanSize "${ROOT_SIZE}")"

			eoutdent # Sizes

			ebegin "Shrinking root partition"
			PART_START="$(fdisk -l "${IMAGE_DEVICE}" 2>/dev/null | awk 'BEGIN{line=0;} /^\// {line++;} (line==2) {print;}' | sed -e 's/^\S*\s*//' -e 's/^\*\s*//' -e 's/\s\s*.*$//')"
			cat <<EOF | fdisk "${IMAGE_DEVICE}" &>/dev/null
d
2
n
p
2
${PART_START}
+$((ROOT_SIZE / 1024))K
w
EOF
			RETURN="$?"
			if [ "${RETURN}" = "0" ] || [ "${RETURN}" = "1" ]; then
				eend 0
			else
				eend $?
			fi

			einfo "Reloading image partitions"
			eindent

			ebegin "Removing loopbacks for partitions"
			kpartx -d "${BUILD_IMAGE}" >/dev/null
			eend $? 1

			ebegin "Setting up loopbacks for partitions"
			IMAGE_DEVICE="$(kpartx -va "${BUILD_IMAGE}" | sed -E 's/.*(loop[0-9][0-9]*)p.*/\1/g' | head -n 1)"
			eend $? 1

			BUILD_BOOT_DEVICE="/dev/mapper/${IMAGE_DEVICE}p1"
			BUILD_ROOT_DEVICE="/dev/mapper/${IMAGE_DEVICE}p2"
			IMAGE_DEVICE="/dev/${IMAGE_DEVICE}"
			
			eoutdent # Reloading image partitions

			ebegin "fsck'ing root filesystem"
			fsck -fy "${BUILD_ROOT_DEVICE}"
			eend $? 1

			ebegin "Growing root filesystem"
			resize2fs "${BUILD_ROOT_DEVICE}"
			eend $?

			ebegin "Trimming image file"
			PART_END="$(fdisk -l "${IMAGE_DEVICE}" 2>/dev/null | awk 'BEGIN{line=0;} /^\// {line++;} (line==2) {print;}' | sed -e 's/^\S*\s*//' -e 's/^\*\s*//' -e 's/^\S*\s*//' -e 's/\s\s*.*$//')"
			PART_UNIT="$(fdisk -l "${IMAGE_DEVICE}" 2>/dev/null | awk '/^Units/ {print $9}')"
			PART_END="$(((PART_END + 1) * PART_UNIT))"
			truncate -s "${PART_END}" "${BUILD_IMAGE}"
			eend $?

			eoutdent # Shrinking image
		fi

		ebegin "Removing loopbacks for partitions"
		kpartx -d "${BUILD_IMAGE}" >/dev/null
		eend $?
	fi

	eoutdent # Finalizing

	einfo "Created ${BUILD_IMAGE}"

# =============================================================================
else
	echo
	einfo "Stage 3"
	echo

	ebegin "Updating APT cache"
	apt-get update >/dev/null
	eend $?

	einfo "Fixing locales"
	eindent

	ebegin "Installing"
	apt-get -y install locales &>/dev/null
	eend $? 1

	ebegin "Configuring"
	sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' -e 's/# en_US ISO-8859-1/en_US ISO-8859-1/' /etc/locale.gen && \
	cat <<'EOF' > /etc/default/locale
LANG="en_US.UTF-8"
LANGUAGE="en_US:en"
EOF
	eend $? 1

	einfo "Building"
	eindent

	dpkg-reconfigure --frontend=noninteractive locales 2>/dev/null | grep '^ ' | sed -e 's/\.\.\..*//' | while read LINE; do
		einfo "${LINE}"
	done

	eoutdent
	eend $? 1

	eoutdent # Fixing locales

	ebegin "Loading debconf selections"
	debconf-set-selections /debconf.set >/dev/null
	eend $? 1

	ebegin "Installing core packages"
	apt-get -y install locales git-core binutils ca-certificates curl wget module-init-tools net-tools wireless-tools dosfstools udhcpc &>/dev/null
	eend $? 1

	einfo "Installing Raspberry Pi software ..."
	eindent

	ebegin "Downloading rpi-update"
	wget -q -O /usr/bin/rpi-update http://goo.gl/1BOfJ >/dev/null
	eend $? 1

	ebegin "Setting permissions on rpi-update"
	chmod +x /usr/bin/rpi-update >/dev/null
	eend $? 1

	ebegin "Creating module playholder"
	mkdir -p /lib/modules/3.1.9+ >/dev/null
	eend $? 1

	ebegin "Creating empty start.elf"
	touch /boot/start.elf >/dev/null
	eend $? 1

	ebegin "Updating"
	rpi-update &>/dev/null
	eend $? 1

	eoutdent # Installing Raspberry Pi software

	ebegin "Installing base packages"
	apt-get -y install console-common ntp openssh-server less vim &>/dev/null
	eend $? 1

	ebegin "Setting root password"
	chpasswd <<< "root:raspberry"
	eend $? 1

	if [ -e /lib/udev/rules.d/75-persistent-net-generator.rules ]; then
		ebegin "Fixing udev network rules"
		sed -i -e 's/KERNEL\!="eth\*|/KERNEL\!="/' /lib/udev/rules.d/75-persistent-net-generator.rules >dev/null
		eend $? 1
	else
		ewarn "/lib/udev/rules.d/75-persistent-net-generator.rules does not exist"
	fi

	if [ -e /etc/udev/rules.d/70-persistent-net.rules ]; then
		ebegin "Removing existing network rules"
		rm -f /etc/udev/rules.d/70-persistent-net.rules >dev/null
		eend $? 1
	else
		einfo "/etc/udev/rules.d/70-persistent-net.rules is already non-existant"
	fi

	cd overlay
	if [ -x overlay.sh ]; then
		ebegin "Stage 4 - Running overlay script"
		./overlay.sh
		eend $? 1

	elif [ -n "$(ls -A1 | grep -v '^.keep$')" ]; then
		ebegin "Stage 4 - Copying overlay to root"
		rsync -aHv * / >/dev/null
		eend $? 1
	fi
	cd /

	einfo "Cleaning up ..."
	eindent

	ebegin "Updating APT cache"
	apt-get update >/dev/null
	eend $?

	#ebegin "Cleaning aptitude"
	#aptitude clean >/dev/null
	#eend $?

	ebegin "Cleaning apt-get"
	apt-get clean >/dev/null
	eend $?

	eoutdent # Cleaning up

	echo
fi
