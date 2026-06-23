EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
COMMA := ,

MM_EXTRA_OPTIONS ?= 
MM_OPTIONS := --arch=loong64 --mode=unshare --keyring=./keyring --dpkgopt='force-confnew' \
--customize-hook='rm -f "$$1"/etc/dpkg/dpkg.cfg.d/99mmdebstrap "$$1"/etc/apt/apt.conf.d/99mmdebstrap' $(MM_EXTRA_OPTIONS)

PVE_CDID = $(strip $(file < pve-cd-id.txt))

RELEASE := 9.2
ISORELEASE := 1
ISO := proxmox-ve_$(RELEASE)-$(ISORELEASE)_loong64.iso

ISO_PACKAGES := libefiboot1t64 \
		libefivar1t64 \
		gettext-base \
		proxmox-grub \
		grub-efi-loong64-unsigned \
		grub-common \
		grub2-common \
		grub-efi-loong64 \
		grub-efi-loong64-bin \
		systemd-boot-tools \
		systemd-boot-efi

.DELETE_ON_ERROR:

all: $(ISO)

/tmp/pve-installer.hook.sh: REL_INFO_B64 = $(shell base64 -w0 release.info)

/tmp/pve-installer.hook.sh: pve-installer.hook.sh.in release.info pve-cd-id.txt
	sed -e 's|@CDID@|$(PVE_CDID)|g' -e 's|@REL_INFO_B64@|$(REL_INFO_B64)|g' $< > $@
	chmod a+x $@

build:
	mkdir -pv build

build/pve-installer.squashfs: PACKAGE_LIST = $(subst $(SPACE),$(COMMA),$(sort $(file < pve-installer.list)))
build/pve-installer.squashfs: pve-loong64.sources pve-installer.list /tmp/pve-installer.hook.sh build pve-iso-init
	mmdebstrap $(MM_OPTIONS) --include='$(PACKAGE_LIST)' --customize-hook='upload pve-iso-init /usr/sbin/pve-iso-init' \
		--customize=/tmp/pve-installer.hook.sh \
		trixie $@ "$<"

build/pve-base.squashfs: PACKAGE_LIST = $(subst $(SPACE),$(COMMA),$(sort $(file < pve-base.list)))
build/pve-base.squashfs: pve-loong64.sources build pve-base.list
	mmdebstrap $(MM_OPTIONS) --include='$(PACKAGE_LIST)' --variant=required \
		trixie $@ "$<"
	mkdir -pv build/proxmox
	unsquashfs -l $@ | wc -l > build/proxmox/pve-base.cnt

build/.disk: release.info build pve-cd-id.txt
	rm -rf build/.disk && mkdir -p build/.disk
	touch build/.disk/$$(date --utc +'%Y-%m-%d-%H-%M-%S.uuid')
	cp -v release.info build/.disk/info
	cp -v release.info build/.cd-info
	cp -v pve-cd-id.txt build/.pve-cd-id.txt
	rsync -av $(CURDIR)/files/ $(CURDIR)/build/
	mkdir -pv build/.base
	mkdir -pv build/.installer
	mkdir -pv build/.installer-mp
	mkdir -pv build/.workdir
	mkdir -pv build/dists/trixie/pve/binary-loong64
	mkdir -pv build/proxmox/packages
	cd build/proxmox/packages && apt download $(ISO_PACKAGES); cd ../../../

build/boot/linux26: build/pve-installer.squashfs
	rm -rf /tmp/pve-iso-tmp && unsquashfs -d /tmp/pve-iso-tmp $< /boot
	cp -v /tmp/pve-iso-tmp/boot/vmlinuz-*-pve build/boot/linux26
	cp -v /tmp/pve-iso-tmp/boot/initrd.img-*-pve build/boot/initrd.img

memtest86+loong64.deb:
	wget http://ftp.cn.debian.org/debian/pool/main/m/memtest86+/memtest86+_8.10-2_loong64.deb -O $@

build/boot/memtest86+loong64: memtest86+loong64.deb build
	rm -rf /tmp/pve-iso-deb-tmp/ && dpkg-deb -x $< /tmp/pve-iso-deb-tmp/
	cp -v /tmp/pve-iso-deb-tmp/boot/mt86+ $@
	rm -rf /tmp/pve-iso-deb-tmp/

$(ISO): build/pve-installer.squashfs build/pve-base.squashfs build/.disk build/boot/linux26 build/boot/memtest86+loong64
	mkdir -p dist
	grub-mkrescue -o $@ build/ -- -as mkisofs -V "PVE" -R

clean:
	rm -rf build dist *.iso *.deb /tmp/pve-installer.hook.sh

.PHONY: clean
