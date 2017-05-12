package App::Monastery::Handler;

use feature ':5.10';
use strict;
use warnings;

our $VERSION = '0.02';

use URI;
use JSON;
use FindBin;
use File::Spec;

use DBM::Deep;
use JSON::RPC::Spec;
use File::Find::Rule;
use Number::Bytes::Human qw(format_bytes);

use Perl::Tidy;
use App::Monastery::Document;

use Class::Tiny qw(_db rpc logger workspace buffer);

sub BUILD {
  my ($self, $args) = @_;

  my $dbm_file = $ENV{MONASTERY_DBM} || File::Spec->catfile( File::Spec->tmpdir, 'app-monastery.db' );
  $self->logger->log(info => '[DBM] Using file: ' . $dbm_file);
  $self->logger->log(info => '[DBM] Using ' . format_bytes( (stat $dbm_file)[7] )) if -f $dbm_file;

  $self->_db({_file => $dbm_file });
  $self->buffer({});
  $self->rpc( JSON::RPC::Spec->new );
}

sub load_from_directory {
  my $self = shift;
  my @dirs = @_ > 1 ? @_ : ($_[0]);

  my @files = File::Find::Rule->new->name('*.pm')->in(@dirs);

  ##################################
  # Parse files and return structure for importing
  my %data;
  foreach my $file (@files) {
    my $doc = App::Monastery::Document->new(file => $file);
    next unless $doc;

    my $record = $doc->record or next;
    $data{packages}{ $doc->package } = $record;
  }

  return \%data;
}

sub db {
  my ($self) = @_;

  return $self->_db->{$$} if $self->_db->{$$}; # return open handle for this process if one exists

  my $dbm = DBM::Deep->new(
    file => $self->_db->{_file},
    locking => 1,
    autoflush => 1,
    num_txns => 3
  );

  # Test DBM
  eval {
    $dbm->begin_work;
    $dbm->{key} = 'foo';
    $dbm->rollback;
  };
  if ($@) { AE::log error => $self->_db->{_file} . ' could not be written'; die }

  $self->_db->{$$} = $dbm;
  return $self->_db->{$$};
}

sub load_buffer {
  my ($self, $uri, $src) = @_;

  my @lines = split /\n/, $src;

  $self->buffer->{$uri} = {
    lines => \@lines,
    doc => App::Monastery::Document->new(buf => $src)
  };
}

sub drop_buffer { delete $_[0]->buffer->{$_[1]} }

sub init {
  my ($self) = @_;

  $self->logger->log(info => __PACKAGE__ . '->init');

  ##################################
  # Check that we haven't tryied to scan @INC
  # recently and if not, scan all modules
  #
  # TODO - un-hardcode timer
  my $reloaded = $self->db->{reloaded} // (time - 3600);
  if ($reloaded > (time - 3600)) {
    $self->logger->log(info => __PACKAGE__ . '->init: skipping run');
  }
  else {
    $self->db->{reloaded} = time;

    unless (my $child = fork) {
      $self->logger->log(info => 'starting scan of @INC');
      my $data = $self->load_from_directory(@INC);
      $self->logger->log(info => 'scan @INC complete');

      # Merge into DBM as a single large commit for performance
      $self->db->begin_work;
      $self->db->import($data);
      $self->db->commit;

      exit;
    }
  }

  ##################################
  # Set up responders for RPC calls

  ##################################
  # Housekeeping
  $self->rpc->register('initialize' => sub {
    my ($params, $match) = @_;

    my $uri = URI->new($params->{rootUri});
    die 'Cannot read directory ' . $uri->file unless -d $uri->file;
    $self->workspace( $uri->file );

    # Parse files in current workspace
    unless (my $child = fork) {
      $self->logger->log(info => 'Loading symbols from ' . $uri->file);
      my $data = $self->load_from_directory($uri->file);

      $self->db->begin_work;
      $self->db->import($data);
      $self->db->commit;

      exit;
    }

    return {
      capabilities => {
        textDocumentSync => 1,                          # Send full document so we can rebuild PPI::Doc
        documentFormattingProvider => JSON::true,       # Support "Format Code" via Perl::Tidy
        documentRangeFormattingProvider => JSON::true,  # Supports range formatting
        documentSymbolProvider => JSON::false,          # Support "Find all symbols" (TODO)
        workspaceSymbolProvider => JSON::false,         # Support "Find all symbols in workspace" (TODO)
        definitionProvider => JSON::false,              # Support "Go to definition" (TODO)
        referencesProvider => JSON::false,              # Support "Find all references" (TODO)
        hoverProvider => JSON::false,                   # Support "Hover"
        completionProvider => {
          resolveProvider => JSON::false,
          triggerCharacters => [ '$', ':', '>' ]
        }
      }
    };
  });

  $self->rpc->register('shutdown' => sub {
    $self->workspace(undef);
    $self->buffer({});
  });

  $self->rpc->register('exit' => sub { exit });

  ##################################
  # Document management
  $self->rpc->register('textDocument/didOpen' => sub {
    $self->load_buffer( $_[0]->{textDocument}{uri}, $_[0]->{textDocument}{text} );
  });

  $self->rpc->register('textDocument/didChange' => sub {
    $self->load_buffer( $_[0]->{textDocument}{uri}, $_[0]->{contentChanges}[0]{text} );
  });

  ##################################
  # Completion
  $self->rpc->register('textDocument/completion' => sub {
    my ($params, $match) = @_;

    my $response = {
      isIncomplete => JSON::true,
      items => []
    };

    my $buffer = $self->buffer->{ $params->{textDocument}{uri} };

    my $line = $buffer->{lines}[ $params->{position}{line} ];
    $self->logger->log(info => 'completion line: ' . $line);

    ##################################
    # Object/class methods
    if ($line =~ /([\$\:\w]+)->\w*$/) {
      ######
      # Instance method
      my $match = $1;
      $self->logger->log(info => "completion: class method ($match)");

      if ($match =~ /\$/) {
        $self->logger->log(info => 'class method: instance');
        my $instances = $buffer->{doc}->object_instances;

        if ($instances->{$match}) {
          $response->{items} = $self->db->{packages}{ $instances->{$match} }{methods} if $self->db->{packages}{ $instances->{$match} };
          $response->{isIncomplete} = JSON::false;

          return $response;
        }
      }
      else {
        ######
        # Class method
        #
        $self->logger->log(info => 'class method: class');
        if ($self->db->{packages}{$match}) {
          $self->logger->log(info => "class method: Found $match");

          # my $dump = Data::Dumper->Dump([$self->db->{packages}{$match}], ['match']);
          # $self->logger->log(info => 'DUMP: ' . $dump);

          $response->{items} = $self->db->{packages}{$match}{methods}->export;
          $response->{isIncomplete} = JSON::false;

          return $response;
        }
      }
    }

    ##################################
    # Package names
    if ($line =~ /([\:\w]+)$/) {
      my $match = $1;
      $self->logger->log(info => "completion: package ($match)");

      my @candidates = grep { $_ =~ /^$match/ } keys %{ $self->db->{packages} };
      @candidates = map { { label => $_ } } @candidates; # formating
      $response->{items} = \@candidates;
    }

    return $response; # fallback
  });

  ##################################
  # Perl::Tidy
  $self->rpc->register('textDocument/formatting' => sub {
    my ($output, $stderr, $log);
    my $buffer = $self->buffer->{ $_[0]->{textDocument}{uri} };

    my $argv;
    $argv .= sprintf '-i %d ', delete $_[0]->{tabSize} if $_[0]{tabSize};
    $argv .= '-t ' if ( exists $_[0]{insertSpaces} && !$_[0]{insertSpaces} );
    delete $_[0]{insertSpaces};

    foreach my $opt (keys %{ $_[0] }) {
      $argv .= sprintf '-%s %s', $opt, $_[0]{$opt};
    }

    my $err = Perl::Tidy::tidy(
      source => $buffer->{lines},
      destination => \$output,
      stderr => \$stderr,
      errorfile => \$stderr,
      logfile => \$log,
      argv => $argv
    );

    return {
      start => { line => 0, character => 0 },
      end => {
        line => scalar @{ $buffer->{lines} },
        character => length $buffer->{lines}[-1]
      },
      newText => $output
    };
  });
}

1;
