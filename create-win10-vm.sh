#!/bin/bash

echo "=== Windows 10 VM Creation Script for Proxmox ==="

read -p "VM ID (e.g., 110): " VMID
read -p "VM Name (e.g., win10-lab): " VMNAME
read -p "Disk size (e.g., 60G): " DISKSIZE
read -p "CPU cores (e.g., 4): " CORES
read -p "Sockets (e.g., 1): " SOCKETS
read -p "RAM in MB (e.g., 8192 for 8GB): " MEMORY
read -p "Storage pool name (e.g., local-lvm): " STORAGE
read -p "Windows 10 ISO path (or leave blank to download): " WINISO
read -p "VirtIO ISO path (or leave blank to download): " VIRTIOISO
read -p "Enable UEFI? (yes/no): " UEFI
read -p "Use SPICE display? (yes/no): " SPICE
read -p "Use autounattend.xml for fully automatic install? (yes/no): " UNATTEND
read -p "Insert Windows license key? (leave blank to skip): " LICENSEKEY

# Optional download of ISO files
if [ -z "$WINISO" ]; then
  echo "Downloading Windows 10 ISO..."
  wget -O windows10.iso "https://software-download.microsoft.com/pr/Win10_22H2_English_x64.iso"
  WINISO="windows10.iso"
fi

if [ -z "$VIRTIOISO" ]; then
  echo "Downloading VirtIO drivers..."
  wget -O virtio-win.iso "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"
  VIRTIOISO="virtio-win.iso"
fi

# Create the VM
echo "Creating VM $VMID..."
qm create $VMID \
  --name $VMNAME \
  --memory $MEMORY \
  --cores $CORES \
  --sockets $SOCKETS \
  --net0 virtio,bridge=vmbr0 \
  --ostype win10 \
  --scsihw virtio-scsi-pci \
  --boot order=virtio0 \
  --ide2 $STORAGE:iso/$VIRTIOISO,media=cdrom \
  --cdrom $STORAGE:iso/$WINISO

# Enable UEFI if selected
if [[ "$UEFI" == "yes" ]]; then
  echo "Enabling UEFI..."
  qm set $VMID --bios ovmf --efidisk0 $STORAGE:32,format=qcow2
fi

# Set display type
if [[ "$SPICE" == "yes" ]]; then
  qm set $VMID --vga qxl --serial0 socket
else
  qm set $VMID --vga std
fi

# Add disk
qm set $VMID --virtio0 $STORAGE:$DISKSIZE

# Add unattend.xml injection if selected
if [[ "$UNATTEND" == "yes" ]]; then
  echo "Creating autounattend floppy..."
  mkdir -p /tmp/autounattend
  cat > /tmp/autounattend/autounattend.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <MetaData wcm:action="add">
              <Key>/IMAGE/INDEX</Key>
              <Value>1</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>0</DiskID>
            <PartitionID>1</PartitionID>
          </InstallTo>
        </OSImage>
      </ImageInstall>
      <UserData>
        <ProductKey>
          <Key>${LICENSEKEY}</Key>
          <WillShowUI>Never</WillShowUI>
        </ProductKey>
        <AcceptEula>true</AcceptEula>
        <FullName>Proxmox User</FullName>
        <Organization>Proxmox Lab</Organization>
      </UserData>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>1</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value>Passw0rd!</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <RegisteredOwner>Proxmox</RegisteredOwner>
      <TimeZone>Central Standard Time</TimeZone>
      <AutoLogon>
        <Username>Administrator</Username>
        <Password>
          <Value>Passw0rd!</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
      </AutoLogon>
    </component>
  </settings>
</unattend>
EOF

  # Create floppy image
  mkfs.vfat -C /tmp/autounattend.img 1440
  mcopy -i /tmp/autounattend.img /tmp/autounattend/autounattend.xml ::/
  qm set $VMID --floppy0 $STORAGE:snippets/autounattend.img
fi

echo "✅ VM $VMID ($VMNAME) created. You can now start the VM using:"
echo "    qm start $VMID"
