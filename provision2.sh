#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status.
set -u  # Treat unset variables as an error when substituting.
set -v  # Print shell input lines as they are read.
set -x  # Print commands and their arguments as they are executed.

# удаляем этот скрипт из автозагрузки:
rm /etc/cron.d/provision

# получаем старый и новый системный раздел по имени системного тома на нём:
OLD_PART=$(sudo pvs --no-headings -o pv_name,lv_name \
  | grep --word-regexp LogVol00Old | awk '{print $1}')
NEW_PART=$(sudo pvs --no-headings -o pv_name,lv_name \
  | grep --word-regexp LogVol00 | awk '{print $1}')

# удаляем старый корневой том:
lvremove --yes /dev/mapper/VolGroup00-LogVol00Old

# перемещаем том LogVol00 на другой диск
pvmove --name LogVol00 "${NEW_PART}" "${OLD_PART}"

# генерируем файлы в /home:
mkdir /home/vagrant/files
for f in {01..20}; do
  dd if=/dev/urandom of="/home/vagrant/files/${f}.bin" bs=4096 count=1
done

# снимаем snapshot /home:
lvcreate --snapshot --size 1G --name SnapHome VolGroup00/LogVolHome

# удаляем часть файлов:
rm /home/vagrant/files/{11..20}.bin -f
ls -la /home/vagrant/files/

# восстанавливаем snapshot:
umount /home
lvconvert --merge VolGroup00/SnapHome
mount /home
ls -la /home/vagrant/files/

# создаём том под /opt, форматируем, добавляем в fstab:
lvcreate --size 4G --name LogVolOpt VolGroup00 "${OLD_PART}"
sleep 1  # ждём обновления информации о томах
mkfs.btrfs -f /dev/mapper/VolGroup00-LogVolOpt

# создаём subvolume @opt на LogVolOpt и делаем его snapshot:
mount /dev/mapper/VolGroup00-LogVolOpt /mnt
btrfs subvolume create /mnt/@opt
btrfs subvolume snapshot /mnt/@opt \
  "/mnt/@opt_snapshot_$(date --iso-8601=seconds)"
umount /mnt

# подключаем cache:
lvconvert --yes --type cache --cachepool CachePool VolGroup00/LogVolOpt

# добавляем /opt в fstab и монтируем:
echo "/dev/mapper/VolGroup00-LogVolOpt /opt btrfs subvol=@opt 0 0" \
  >> /etc/fstab
mount /opt
