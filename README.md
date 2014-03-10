# repo-mirror - A tool to mirror linux repositories.

repo-mirror is a tool to mirror linux repositories and to tag them.

## Supported Repositories

Currently repo-mirror is in early development stage. Right now only *yum* repositories are supported.


## Configuration

To configure repo-mirror create a configuration file */etc/rex/repo-mirror.conf*.

```
RepositoryRoot = /data/repositories

<Log4perl>
  config = log4perl.conf
</Log4perl>


# this will create the repository inside /data/repositories/head/CentOS/6/rex/x86_64
<Repository rex-centos-6-x86-64>
  url   = http://nightly.rex.linux-files.org/CentOS/6/rex/x86_64
  local = CentOS/6/rex/x86_64
  type  = Yum
</Repository>
```

You also need to create a Log4perl configuration file. You can set the location in repo-mirror.conf file.

```
log4perl.rootLogger                    = DEBUG, FileAppndr1

log4perl.appender.FileAppndr1          = Log::Log4perl::Appender::File
log4perl.appender.FileAppndr1.filename = /var/log/repo-mirror.log
log4perl.appender.FileAppndr1.layout   = Log::Log4perl::Layout::SimpleLayout
```

## Mirror a repository

To mirror a defined repository you can use the following command:

```
repo-mirror --mirror --repo=rex-centos-6-x86-64
```

To mirror every configured directory, you can use the **all** keyword.

```
repo-mirror --mirror --repo=all
```

To reload the metadata of a repository there is the *--update-metadata* option.

```
repo-mirror --mirror --repo=rex-centos-6-x86-64 --update-metadata
```

To reload all package files of a repository there is the *--update-files* option.

```
repo-mirror --mirror --repo=rex-centos-6-x86-64 --update-files
```


## Tagging

Every repository is per default stored in the *head* tag. If you want to create stable tags for your production servers,
you can do this with the *--tag* option.

A tag is just a hardlinked copy of the *head* tag.

```
repo-mirror --tag=production --repo=rex-centos-6-x86-64
```
