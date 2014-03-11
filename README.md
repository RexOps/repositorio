## repositorio - A tool to mirror and administrate linux repositories.

repositorio is a tool to mirror and administrate linux repositories and to tag them.

### Supported Repositories

Currently repositorio is in early development stage. Right now only *yum* repositories are supported.


### Configuration

To configure repositorio create a configuration file */etc/rex/repositorio.conf*.

```
RepositoryRoot = /data/repositories

<Log4perl>
  config = log4perl.conf
</Log4perl>


# this will create the repository inside
# /data/repositories/head/rex-centos-6-x86-64/CentOS/6/rex/x86_64
<Repository rex-centos-6-x86-64>
  url   = http://nightly.rex.linux-files.org/CentOS/6/rex/x86_64
  local = rex-centos-6-x86-64/CentOS/6/rex/x86_64
  type  = Yum
</Repository>
```

You also need to create a Log4perl configuration file. You can set the location in repositorio.conf file.

```
log4perl.rootLogger                    = DEBUG, FileAppndr1

log4perl.appender.FileAppndr1          = Log::Log4perl::Appender::File
log4perl.appender.FileAppndr1.filename = /var/log/repositorio.log
log4perl.appender.FileAppndr1.layout   = Log::Log4perl::Layout::SimpleLayout
```

### Mirror a repository

To mirror a defined repository you can use the following command:

```
repositorio --mirror --repo=rex-centos-6-x86-64
```

To mirror every configured directory, you can use the **all** keyword.

```
repositorio --mirror --repo=all
```

To reload the metadata of a repository there is the *--update-metadata* option.

```
repositorio --mirror --repo=rex-centos-6-x86-64 --update-metadata
```

To reload all package files of a repository there is the *--update-files* option.

```
repositorio --mirror --repo=rex-centos-6-x86-64 --update-files
```

### Managing a repository

If you need to create a custom repository, you can do this as well.

Just add the repository to your configuration file:

```
<Repository custom-centos-6-x86-64>
  url   = http://ftp.uni-koeln.de/mirrors/fedora/epel/6/x86_64/
  local = custom-centos-6-x86-64/CentOS/6/custom/x86_64/
  type  = Yum
</Repository
```

Initialize the repository:

```
repositorio --init --repo=custom-centos-6-x86-64
```

Now you can add and remove files from this directory.

```
repositorio --add-file=my-package-1.0.rpm --repo=custom-centos-6-x86-64
repositorio --remove-file=my-package-0.9.rpm --repo=custom-centos-6-x86-64
```


### Tagging

Every repository is per default stored in the *head* tag. If you want to create stable tags for your production servers,
you can do this with the *--tag* option.

A tag is just a hardlinked copy of the *head* tag.

```
repositorio --tag=production --repo=rex-centos-6-x86-64
```
