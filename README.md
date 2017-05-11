# NAME

App::Monastery - Perl Language Server

# DESCRIPTION

App::Monastery is a language server conforming to the [spec](https://github.com/Microsoft/language-server-protocol/blob/master/protocol.md). Currently
Monastery supports a subset of v3.0 of the protocol.

More can be read about what a Language Server is for at [http://langserver.org](http://langserver.org)
but the idea is to allow editors/IDEs to support a variety of languages
without needing to reimplement lang-specific features themselves or,
as in most cases, not implementing them at all.

This server is very much **alpha quality** but it has some mildly
intelligent completion options and should be easily expanded with
[Perl::Tidy](https://metacpan.org/pod/Perl::Tidy) to handle formatting and `perl -c` or [Perl::Critic](https://metacpan.org/pod/Perl::Critic)
to provide more useful diagnostics to the user.

# INSTALLATION

This can be installed from the repo directly or for convenience, there
is a fatpacked version in author/.

    # install using cpanm
    cpanm -i git@github.com:ccakes/p5-app-monastery.git

    # or download fatpacked script
    curl -sL -o /usr/local/bin/monastery-fatpack https://raw.githubusercontent.com/ccakes/p5-app-monastery/master/author/monastery-fatpack

# TODO

- Handler.pm

    This file is a mess, the `$rpc-`register> calls need to be abstracted,
    ideally into a controller-type model to make adding functionality
    simpler.

- textDocument/publishDiagnostics

    Need to work out when best to trigger this, probably on
    `textDocument/willSave`. `didChange` would be nicer but a bit
    spammy. This should be `perl -c` rather as it's syntax errors.

- textDocument/rangeFormatting
- workspace/symbol + textDocument/documentSymbol
- Some tests...

# LICENSE

Copyright (C) Cameron Daniel.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Cameron Daniel <cam.daniel@gmail.com>
