## repositorio - A tool to mirror and administrate linux repositories.

repositorio is a tool to mirror and administrate linux repositories and to tag them.

This is the master branch of the development repository. In this branch you'll find all the new stuff that is work-in-progress.

### Need help?

If you need help, feel free to join us on irc.freenode.net on channel #rex (this is the channel for all RexOps projects) or just post an issue in the tracker.

### Supported Repositories

Right now *yum* and *apt* repositories are supported. It is also possible to query errata for packages if an errata database is present. See *errata* chapter for more information.

Currently we're working on *docker* support, so that it is possible to build a private docker registry with repositorio. See *docker* chapter for more information.


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

### Errata

It is also possible to query repositorio for the errata of a package. You can do this via command line and via a webservice. If you want to query errata you also need the errata database. Currently we provide CentOS (5, 6 and 7) and EPEL errata databases.

If you want to contribute scripts to generate errata databases for other distributions, feel free to send us a pull request or join us on irc (irc.freenode.net / #rex).

To configure a repository to serve also the errata, you need to configure the errata type for the repository.

```
<Repository centos-6-x86-64>
  url    = http://ftp.hosteurope.de/mirror/centos.org/6/os/x86_64/
  local  = centos-6-x86-64/CentOS/6/rex/x86_64/
  type   = Yum
  errata = CentOS-6
</Repository>
```

To query the errata database you can run the following command:

```
repositorio --repo=some-repo --errata --package=openssl --arch=x86_64 --version=1.0.0-20.el6_2.3
```

If you want to query the webinterface, this will return a json structure containing all available updates:

```
curl -XGET \
  http://your-server:3000/head/centos-6-x86-64/errata?package=openssl&arch=x86_64&version=1.0.0-20.el6_2.3
```

### Serving a directory

To serve a directory we advice you to use Apache or nginx. You can just point the document root to *RepositoryRoot* in your repositorio.conf file.

If you don't want to install a webserver, you can also use the build-in webserver to server repositories.

```
repositorio --repo=repo-name --server prefork
```

### Docker

If you also want to manage your private docker registry with repositorio you can do this as well. Currently this feature is in an early development stage. We welcome any feedback and patches.

Current development stage:

* upload images (docker push) - done
* download images (docker pull) - done
* authentication (docker login) - done
* user management - open
* permissions to repositories - open
* search for images (docker search) - done

#### Configuration

To create a docker repository you need the following snippet inside your repositorio.conf file.

```
<Repository docker>
  local = docker-images
  type  = Docker
</Repository>
```

And then you can initialize this repository as usual with:

```
repositorio --repo=docker --init
```

This will create a new folder *docker-images* inside your *RepositoryRoot*/head directory.

For the docker images it is not possible to use apache (or another webserver) to serve the content, so you need to start a small server that is included with repositorio.

```
repositorio --repo=docker --server prefork
```

This will start a preforking webserver. The server part is done with Mojolicious. Mojolicious is an easy to use Perl Webframework.

Now you can use *repositorio* as a docker registry.

First you need to create a user:

```
docker login -e some@mail.tld -p 'some-save-password' -u 'some-user' http://localhost:3000/v1/
```

The user is enabled immediately.
Then you can push and pull images.

```
docker pull ubuntu
docker tag localhost:3000/ubuntu
docker push localhost:3000/ubuntu
```




