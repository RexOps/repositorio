use Test::More;

use_ok 'Rex::Repositorio';
use_ok 'Rex::Repositorio::Repository_Factory';
use_ok 'Rex::Repositorio::Repository::Base';
use_ok 'Rex::Repositorio::Repository::Yum';

my $r = Rex::Repositorio::Repository_Factory->create(type => 'Yum', options => {});
ok(ref $r, 'got repo object');


done_testing();
