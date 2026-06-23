EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
COMMA := ,

MM_EXTRA_OPTIONS ?= 
MM_OPTIONS := --arch=loong64 --mode=unshare --keyring=./keyring --dpkgopt='force-confnew' \
--customize-hook='rm -f "$$1"/etc/dpkg/dpkg.cfg.d/99mmdebstrap "$$1"/etc/apt/apt.conf.d/99mmdebstrap' $(MM_EXTRA_OPTIONS)

PVE_CDID = $(strip $(file < pve-cd-id.txt))

DEBIAN_RELEASE := trixie
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
		systemd-boot-efi \
		ifupdown2

.DELETE_ON_ERROR:

all: $(ISO)

/tmp/pve-installer.hook.sh: REL_INFO_B64 = $(shell base64 -w0 release.info)

/tmp/pve-installer.hook.sh: pve-installer.hook.sh.in release.info pve-cd-id.txt
	sed -e 's|@CDID@|$(PVE_CDID)|g' -e 's|@REL_INFO_B64@|$(REL_INFO_B64)|g' $< > $@
	chmod a+x $@

build:
	mkdir -pv build

release.info: release.info.in
	sed -e's|@RELEASE@|$(RELEASE)|g' -e's|@ISORELEASE@|$(ISORELEASE)|g' $< > $@

build/pve-installer.squashfs: PACKAGE_LIST = $(subst $(SPACE),$(COMMA),$(sort $(file < pve-installer.list)))
build/pve-installer.squashfs: pve-loong64.sources pve-installer.list /tmp/pve-installer.hook.sh build pve-iso-init
	mmdebstrap $(MM_OPTIONS) --include='$(PACKAGE_LIST)' --customize-hook='upload pve-iso-init /usr/sbin/pve-iso-init' \
		--customize=/tmp/pve-installer.hook.sh \
		$(DEBIAN_RELEASE) $@ "$<"

build/pve-base.squashfs: PACKAGE_LIST = $(subst $(SPACE),$(COMMA),$(sort $(file < pve-base.list)))
build/pve-base.squashfs: pve-loong64.sources build pve-base.list
	mmdebstrap $(MM_OPTIONS) --include='$(PACKAGE_LIST)' --variant=required \
		--customize-hook='rm -rf "$$1"/etc/network/interfaces*' \
		$(DEBIAN_RELEASE) $@ "$<"
	mkdir -pv build/proxmox
	unsquashfs -l $@ | wc -l > build/proxmox/pve-base.cnt

build/proxmox/packages: fetch-packages.sh
	mkdir -pv build/proxmox/packages
	$(CURDIR)/fetch-packages.sh build/proxmox/packages $(ISO_PACKAGES)

build/.disk: release.info build pve-cd-id.txt build/proxmox/packages
	rm -rf build/.disk && mkdir -p build/.disk
	touch build/.disk/$$(date --utc +'%Y-%m-%d-%H-%M-%S.uuid')
	cp -v release.info build/.disk/info
	cp -v release.info build/.cd-info
	cp -v pve-cd-id.txt build/.pve-cd-id.txt
	rsync -av $(CURDIR)/files/ $(CURDIR)/build/
	mkdir -pv build/.base build/.installer build/.installer-mp build/.workdir
	mkdir -pv build/dists/$(DEBIAN_RELEASE)/pve/binary-loong64
	sed -i -e's|@RELEASE@|$(RELEASE)|g' -e's|@ISORELEASE@|$(ISORELEASE)|g' $(CURDIR)/build/boot/grub/pvetheme/theme.txt

build/boot/linux26: build/pve-installer.squashfs
	rm -rf /tmp/pve-iso-tmp && unsquashfs -d /tmp/pve-iso-tmp $< /boot /usr/lib/grub/loongarch64-efi
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
	grub-mkrescue -d /tmp/pve-iso-tmp/usr/lib/grub/loongarch64-efi -o $@ build/ -- -as mkisofs -V "PVE" -R

clean:
	rm -rf build dist *.iso *.deb /tmp/pve-installer.hook.sh release.info

.PHONY: clean
