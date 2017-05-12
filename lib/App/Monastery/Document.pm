package App::Monastery::Document;

use feature ':5.10';
use strict;
use warnings;

use PPI;
use List::Util qw(first sum);

use Class::Tiny qw(file buf is_package _doc _mtime);

sub BUILD {
  my ($self, $args) = @_;
  return unless $args->{file} or $args->{buf};

  if ($args->{file}) {
    return unless -f $args->{file};

    $self->file( $args->{file} );
    $self->_mtime( (stat $args->{file})[9] );
    $self->_doc( PPI::Document->new($self->file) );
  }
  else {
    $self->_doc( PPI::Document->new(\$self->buf) );
  }

  $self->is_package( $self->_doc->find_any('PPI::Statement::Package') );
}

sub package {
  my ($self) = @_;

  my $package = $self->_doc->find_first('PPI::Statement::Package');
  return $package ? $package->namespace : undef;
}

sub parents {
  my ($self) = @_;

  my $parents = $self->_doc->find(
    sub {
      return 0 unless $_[1]->isa('PPI::Statement'); # only look at Statements, not POD!

      ####
      # Find any use base/parent/Mojo::Base or Moose-style extends inheritance
      return 1 if $_[1]->isa('PPI::Statement::Include') && $_[1]->content =~ /use (parent|base|['"]?Mojo::Base['"]?) /;
      return 1 if ($_[1]->children)[0]->isa('PPI::Token::Word') and ($_[1]->children)[0]->content eq 'extends';

      return 0;
    }
  );

  return [] unless $parents;    # no results

  my %list;
  foreach my $parent (@{$parents}) {
    my $mod = first { $_->isa('PPI::Token::Quote') || $_->isa('PPI::Token::QuoteLike') } reverse $parent->children;
    next unless $mod;

    ####
    # Parse out name based on quote type
    if ($mod->isa('PPI::Token::Quote')) {
      my $name = $mod->content;
      $name =~ s/['"]//g;

      $list{$name} = undef;
    }
    elsif ($mod->isa('PPI::Token::QuoteLike')) {
      $list{$_} = undef foreach $mod->literal;
    }
  }

  my @par = keys %list;
  return \@par;
}

sub methods {
  my ($self) = @_;

  my $subs = $self->_doc->find('PPI::Statement::Sub');
  return [] unless $subs;

  my %list;
  foreach my $sub (@{$subs}) {
    next if $sub->name =~ /(BUILD|BUILDARGS|DESTROY|AUTOLOAD)/;

    $list{ $sub->name } = {
      label => $sub->name,
      #kind => $self->is_package ? 2 : 3,  # method vs function
    };
  }

  my @methods = values %list;
  return \@methods;
}

sub tokens {
  my ($self) = @_;

  my $tokens = $self->_doc->find('PPI::Statement::Variable');
  return [] unless $tokens;

  my %list;
  foreach my $token (@{$tokens}) {
    my $word = $token->find_first('PPI::Token::Word');
    my $symbol = $token->find_first('PPI::Token::Symbol');

    next unless $word; # no strict, too hard to tell
    next if $self->is_package and $word->content eq 'my'; # only our in packages

    $list{ $symbol->content } = {
      label => $symbol->content,
      #kind => $self->is_package ? 5 : 6,  # field vs variable
    };
  }

  my @symbols = values %list;
  return \@symbols;
}

sub object_instances {
  my ($self) = @_;

  my $vars= $self->_doc->find('PPI::Statement::Variable');
  return [] unless $vars;

  my %list;
  foreach my $var (@{$vars}) {
    if ($var->content =~ /([\w:]+)->new/ || $var->content =~ /new ([\w:]+)/) {
      my $inst = $var->find_first('PPI::Token::Symbol');
      $list{ $inst->content } = $1;
    }
  }

  if ($self->is_package) {
    $list{'$self'} = $self->package;
  }

  return \%list;
}

sub record {
  my ($self) = @_;

  return unless $self->is_package;

  return {
    _file => $self->file,
    _mtime => $self->_mtime,

    parents => $self->parents,
    methods => $self->methods,
    tokens => $self->tokens
  };
}

1;
