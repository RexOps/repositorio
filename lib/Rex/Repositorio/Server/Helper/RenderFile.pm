#
# bold copied from Mojolicious::Plugin::RenderFile - because there are no rpm packages
#
package Rex::Repositorio::Server::Helper::RenderFile;
use Mojo::Base 'Mojolicious::Plugin';

use strict;
use warnings;
use File::Basename;
use Encode qw( encode decode_utf8 );
use Mojo::Util 'quote';

our $VERSION = '0.08';

sub register {
    my ( $self, $app ) = @_;

    $app->helper( 'render_file' => sub {
        my $c        = shift;
        my %args     = @_;

        utf8::decode($args{filename}) if $args{filename} && !utf8::is_utf8($args{filename});
        utf8::decode($args{filepath}) if $args{filepath} && !utf8::is_utf8($args{filepath});

        my $filename            = $args{filename};
        my $status              = $args{status}               || 200;
        my $content_disposition = $args{content_disposition}  || 'attachment';
        my $cleanup             = $args{cleanup} // 0;

        # Content type based on format
        my $content_type;
        $content_type = $c->app->types->type( $args{format} ) if $args{format};
        $content_type ||= 'application/x-download';

        # Create asset
        my $asset;
        if ( my $filepath = $args{filepath} ) {
            unless ( -f $filepath && -r $filepath ) {
                $c->app->log->error("Cannot read file [$filepath]. error [$!]");
                return;
            }

            $filename ||= fileparse($filepath);
            $asset = Mojo::Asset::File->new( path => $filepath );
            $asset->cleanup($cleanup);
        } elsif ( $args{data} ) {
            $filename ||= $c->req->url->path->parts->[-1] || 'download';
            $asset = Mojo::Asset::Memory->new();
            $asset->add_chunk( $args{data} );
        } else {
            $c->app->log->error('You must provide "data" or "filepath" option');
            return;
        }

        # Create response headers
        $filename = quote($filename); # quote the filename, per RFC 5987
        $filename = encode("UTF-8", $filename);

        my $headers = Mojo::Headers->new();
        $headers->add( 'Content-Type', $content_type . ';name=' . $filename );
        $headers->add( 'Content-Disposition', $content_disposition . ';filename=' . $filename );

        # Range
        # Partially based on Mojolicious::Static
        if ( my $range = $c->req->headers->range ) {
            my $start = 0;
            my $size  = $asset->size;
            my $end   = $size - 1 >= 0 ? $size - 1 : 0;

            # Check range
            if ( $range =~ m/^bytes=(\d+)-(\d+)?/ && $1 <= $end ) {
                $start = $1;
                $end = $2 if defined $2 && $2 <= $end;

                $status = 206;
                $headers->add( 'Content-Length' => $end - $start + 1 );
                $headers->add( 'Content-Range'  => "bytes $start-$end/$size" );
            } else {
                # Not satisfiable
                return $c->rendered(416);
            }

            # Set range for asset
            $asset->start_range($start)->end_range($end);
        } else {
            $headers->add( 'Content-Length' => $asset->size );
        }

        # Set response headers
        $c->res->content->headers($headers);

        # Stream content directly from file
        $c->res->content->asset($asset);
        return $c->rendered($status);
    } );
}

1;

=head1 NAME

Mojolicious::Plugin::RenderFile - "render_file" helper for Mojolicious

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('RenderFile');

    # Mojolicious::Lite
    plugin 'RenderFile';

    # In controller
    $self->render_file('filepath' => '/tmp/files/file.pdf'); # file name will be "file.pdf"

    # Provide any file name
    $self->render_file('filepath' => '/tmp/files/file.pdf', 'filename' => 'report.pdf');

    # Render data from memory as file
    $self->render_file('data' => 'some data here', 'filename' => 'report.pdf');

    # Open file in browser(do not show save dialog)
    $self->render_file(
        'filepath' => '/tmp/files/file.pdf',
        'format'   => 'pdf',                 # will change Content-Type "application/x-download" to "application/pdf"
        'content_disposition' => 'inline',   # will change Content-Disposition from "attachment" to "inline"
        'cleanup'  => 1,                     # delete file after completed
    );

=head1 DESCRIPTION

L<Mojolicious::Plugin::RenderFile> is a L<Mojolicious> plugin that adds "render_file" helper. It does not read file in memory and just streaming it to a client.

=head1 HELPERS

=head2 C<render_file>

    $self->render_file(filepath => '/tmp/files/file.pdf', 'filename' => 'report.pdf' );

With this helper you can easily provide files for download. By default "Content-Type" header is "application/x-download" and "content_disposition" option value is "attachment".
Therefore, a browser will ask where to save file. You can provide "format" option to change "Content-Type" header.


=head3 Supported Options:

=over

=item C<filepath>

Path on the filesystem to the file. You must always pass "filepath" or "data" option

=item C<data>

Binary content which will be transfered to browser. You must always pass "filepath" or "data" option

=item C<filename> (optional)

Browser will use this name for saving the file

=item C<format> (optional)

The "Content-Type" header is based on the MIME type mapping of the "format" option value.  These mappings can be easily extended or changed with L<Mojolicious/"types">.

By default "Content-Type" header is "application/x-download"

=item C<content_disposition> (optional)

Tells browser how to present the file.

"attachment" (default) - is for dowloading

"inline" - is for showing file inline

=item C<cleanup> (optional)

Indicates if the file should be deleted when rendering is complete

=back

This plugin respects HTTP Range headers.

=head1 AUTHOR

Viktor Turskyi <koorchik@cpan.org>

=head1 CONTRIBUTORS

Nils Diewald (Akron)

=head1 BUGS

Please report any bugs or feature requests to Github L<https://github.com/koorchik/Mojolicious-Plugin-RenderFile>

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

Copyright 2011 Viktor Turskyi

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=cut
