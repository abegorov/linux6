# Работа с LVM

## Задание

1. Уменьшить том под **/** до **8G**
2. Выделить том под **/home**
3. Выделить том под **/var** (**/var** - сделать в **mirror**)
4. Для **/home** - сделать том для снэпшотов
5. Прописать монтирование в **fstab** (попробовать с разными опциями и разными файловыми системами на выбор)
6. Работа со снапшотами:

    - сгенерировать файлы в **/home/**;
    - снять снэпшот;
    - удалить часть файлов;
    - восстановиться со снэпшота.

7. Попробовать поставить **btrfs/zfs**:

    - с кешем и снэпшотами;
    - разметить здесь каталог **/opt**.

## Реализация

Задание сделано в 2 этапа для образа **centos/7** версии **1804.02** (с другими версиями не работает). **Vagrantfile** был изменён с целью создания дисков в директории с виртуальной машиной, имя машины в хеш-таблице **MACHINES** должно быть уникальное. Машина создаётся в директории **vbox_vms_dir**, значение которой получается из свойства **Default machine folder:** в выводе команды **VBoxManage list systemproperties** на хосте, где выполняется **vagrant up**.

Выполнение выполняется в 2 этапа:

1. После загрузки запускается скрипт **[provision.sh](https://github.com/abegorov/linux6/blob/main/provision.sh)**, который создаёт тома (кроме **btrfs**), переносит систему на диск меньшего размера и перезагружает машину.
2. После перезагрузки запускается скрипт **[provision2.sh](https://github.com/abegorov/linux6/blob/main/provision2.sh)**, который возвращает систему на изначальный диск, создаёт том **btrfs**, осуществляет работу со снэпшотами **/home**.

Скрипт **[provision.sh](https://github.com/abegorov/linux6/blob/main/provision.sh)**:

1. Ставит **gdisk** и **xfsdump** (репозитории **CentOS** уже недоступны, поэтому предварительно меняется путь к ним).
2. Находит системный диск, 2 диска под зеркало (2 самых маленьких), дополнительный диск (самый большой, кроме системного), диск по **/home** (оставшийся).
3. На всех дисках (кроме системного) создаётся **gpt** раздел с типом **lvm** под весь размер дисках.
4. Создаётся тома под **/home**, **/var**, **/** размером **8G** и **CachePool** для будущего **/opt** в **btrfs**.
5. Создаётся снэпшот корневой файловой системы, после чего данные с него копируются на новые **/home**, **/var**, **/** тома.
6. По окончанию копирования данных снэпшот удаляется, а **/home** и **/var** добавляются в **/etc/fstab** (по имени устройства, чтобы избежать проблем с одинаковым **UUID** при создании снэпшотов). **/home** добавляется с опцией монтирования **atime**, чтобы обновлять дату доступа к файла, а **/var** монтируется с **data=journal**, чтобы включить журналирование данных (помимо метаданных).
7. Старый системный том переименовывается из **LogVol00** в **LogVol00Old**, а новый системный диск переименовывается в **LogVol00**, что позволяет избежать конфигурирование загрузчика.
8. Скрипт **[provision2.sh](https://github.com/abegorov/linux6/blob/main/provision2.sh)** прописывается в автозагрузку (создаётся файл **/etc/cron.d/provision**).
9. Виртуальная машина перезагружается.

После перезагрузки виртуальной машины запускается скрипт **[provision2.sh](https://github.com/abegorov/linux6/blob/main/provision2.sh)**, который логируется своё выполнения в **[provision2.log](https://github.com/abegorov/linux6/blob/main/provision2.log)** и выполняется следующие действия:

1. Удаляет скрипт **[provision2.sh](https://github.com/abegorov/linux6/blob/main/provision2.sh)** из автозагрузки.
2. Находит раздел под старый и новый системный диск.
3. Старым системный том удаляется.
4. Новый системный том перемещается на физический том, где ранее был старый системный раздел с помощью **pvmove**.
5. На разделе **/home** генерятся файлы, создаётся снэпшот, удаляется часть файлов, восстанавливается снэпшот.
6. Создаётся кэшированный том под **/opt**, форматируется в **btrfs**. Средствами **btrfs** создаётся подтом **@opt**, делается его снэпшот и подтом **@opt** прописывается в **/etc/fstab** и монтируется.

## Результаты

- [измененный Vagrantfile](https://github.com/abegorov/linux6/blob/main/Vagrantfile);
- [скрипт настройки - 1ый этап](https://github.com/abegorov/linux6/blob/main/provision.sh);
- [скрипт настройки - 2ой этап](https://github.com/abegorov/linux6/blob/main/provision2.sh);
- [лог выполнения скрипта настройки 2ого этапа](https://github.com/abegorov/linux6/blob/main/provision2.log);
- [вывод команды lsblk до решения](https://github.com/abegorov/linux6/blob/main/lsblk-before.txt);
- [вывод команды lsblk после решения](https://github.com/abegorov/linux6/blob/main/lsblk-after.txt);
- [вывод команды btrfs subvolume list /opt со списком snapshot'ов](https://github.com/abegorov/linux6/blob/main/btrfs-snapshot.txt).

## Запуск

Необходимо скачать **VagrantBox** для **centos/7** версии **1804.02** и добавить его в **Vagrant** под именем **centos/7/1804.02**. Сделать это можно командами:

```shell
curl -O https://cloud.centos.org/centos/7/vagrant/x86_64/images/CentOS-7-x86_64-Vagrant-1804_02.VirtualBox.box
vagrant box add CentOS-7-x86_64-Vagrant-1804_02.VirtualBox.box --name "centos/7/1804.02"
```

После этого достаточно сделать **vagrant up**, при запуске будет автоматически запущен скрипт **[provision.sh](https://github.com/abegorov/linux5/blob/main/provision.sh)**, который сделает все указанные выше настройки. Протестировано в **Vagrant 2.3.7**.
