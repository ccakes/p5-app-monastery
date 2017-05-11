package App::Monastery;

use feature ':5.10';
use strict;
use warnings;

our $VERSION = '0.01';

use AE;
use AnyEvent::Log;
use AnyEvent::Handle;

use JSON;
use Encode;
use FindBin;
use File::Spec;
use Getopt::Long;

use IO::Handle;
STDOUT->autoflush(1);

use Time::HiRes ();
use constant START => Time::HiRes::time;

use App::Monastery::Handler;

sub run {
  my %options = (log => 'warn');
  Getopt::Long::GetOptions(
    \%options,
    'log|l'
  );

  ######
  # Setup AE::log format
  my $INIT = Time::HiRes::time;
  AnyEvent::Log::ctx->fmt_cb(sub {
    my $ts = sprintf '%.03f s', (Time::HiRes::time - $INIT);
    my @res;

    for (split /\n/, sprintf "%-5s %s: %s", $AnyEvent::Log::LEVEL2STR[$_[2]], $_[1][0], $_[3]) {
      push @res, "$ts [$$] $_\n";
    }

    join '', @res;
  });

  AnyEvent::Log::ctx->level( $options{log} );
  AnyEvent::Log::ctx->log_to_file('/tmp/perl-lang-server.log');

  my $handler = App::Monastery::Handler->new(logger => AnyEvent::Log::ctx());
  $handler->init;

  my $hdl; $hdl = AnyEvent::Handle->new(
    fh => \*STDIN,
    on_error => sub {
      AE::log error => 'on_error: ' . $_[2];
      $hdl->destroy;
      exit;
    },
    on_eof => sub {
      AE::log info => 'Client disconnected';
      $hdl->destroy;
      exit;
    }
  );

  $hdl->on_read(sub {
    my ($h) = @_;

    $h->push_read(line => "\015\012\015\012", sub {
      AE::log debug => 'header: ' . $_[1];
    });

    $h->push_read(json => sub {
      my $json = JSON->new->utf8(1)->canonical(1)->encode($_[1]);
      AE::log debug => 'data: ' . $json;

      my $response = $handler->rpc->parse($json);
      return unless $response;

      my $length = length $response;
      AE::log info => 'resp: ' . $response;

      print "Content-Length: $length\r\n\r\n$response";
    });
  });

  AE::cv->recv;
}


1;
__END__

=encoding utf-8

=head1 NAME

App::Monastery - Perl Language Server

=head1 DESCRIPTION

App::Monastery is a language server conforming to the L<spec|https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md>. Currently
Monastery supports a subset of v3.0 of the protocol.

More can be read about what a Language Server is for at L<http://langserver.org>
but the idea is to allow editors/IDEs to support a variety of languages
without needing to reimplement lang-specific features themselves or,
as in most cases, not implementing them at all.

This server is very much B<alpha quality> but it has some mildly
intelligent completion options and should be easily expanded with
L<Perl::Tidy> to handle formatting and C<perl -c> or L<Perl::Critic>
to provide more useful diagnostics to the user.

=head1 INSTALLATION

This can be installed from the repo directly or for convenience, there
is a fatpacked version in author/.

  # install using cpanm
  cpanm -i git@github.com:ccakes/p5-app-monastery.git

  # or download fatpacked script
  curl -sL -o /usr/local/bin/monastery-fatpack https://raw.githubusercontent.com/ccakes/p5-app-monastery/master/author/monastery-fatpack

=head1 TODO

=over 4

=item Handler.pm

This file is a mess, the C<$rpc->register> calls need to be abstracted,
ideally into a controller-type model to make adding functionality
simpler.

=item textDocument/publishDiagnostics

Need to work out when best to trigger this, probably on
C<textDocument/willSave>. C<didChange> would be nicer but a bit
spammy. This should be C<perl -c> rather as it's syntax errors.

=item textDocument/rangeFormatting

=item workspace/symbol + textDocument/documentSymbol

=item Some tests...

=back

=head1 LICENSE

Copyright (C) Cameron Daniel.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Cameron Daniel E<lt>cam.daniel@gmail.comE<gt>

=cut

