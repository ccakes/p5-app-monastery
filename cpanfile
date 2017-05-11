requires 'perl', '5.10.0';

requires 'JSON';
requires 'JSON::RPC::Spec';

requires 'PPI';
requires 'Perl::Tidy';
requires 'Perl::Critic';

requires 'AnyEvent';
requires 'DBM::Deep';
requires 'Class::Tiny';
requires 'Getopt::Long';
requires 'File::Find::Rule';
requires 'Number::Bytes::Human';

on 'test' => sub {
    requires 'Test::More', '0.98';
};

