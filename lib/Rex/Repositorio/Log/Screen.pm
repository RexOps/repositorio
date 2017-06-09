package Rex::Repositorio::Log::Screen;

use base qw(Log::Dispatch::Screen);
use DateTime;

sub new {
  my $proto = shift;
  return $proto->SUPER::new(@_);
}

sub log_message {
  my $self = shift;
  my %p    = @_;

  my $dt = DateTime->now;

  my $message =
    $self->{utf8} ? encode( 'UTF-8', $p{message} ) : $p{message};
  if ( $self->{stderr} ) {
    print STDERR $dt->iso8601() . $dt->strftime('%Z') . " ";
    print STDERR $message;
  }
  else {
    print STDOUT $dt->iso8601() . $dt->strftime('%Z') . " ";
    print STDOUT $message;
  }
}

1;
