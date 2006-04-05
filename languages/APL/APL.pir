.include 'errors.pasm'

.sub _main :main
    .param pmc args

    errorson .PARROT_ERRORS_PARAM_COUNT_FLAG

    load_bytecode 'TGE.pbc'
    load_bytecode 'languages/APL/lib/APLGrammar.pbc'
    load_bytecode 'languages/APL/lib/ASTGrammar.pbc'
    load_bytecode 'languages/APL/lib/OSTGrammar.pbc'
    load_bytecode 'languages/APL/lib/PIRGrammar.pbc'
    load_bytecode 'languages/APL/lib/PAST.pbc'
    load_bytecode 'languages/APL/lib/POST.pbc'
    load_bytecode 'languages/APL/lib/APLOpLookup.pbc'

    .local string source
    source = _get_source(args)

    # Match against the source
    .local pmc match
    .local pmc start_rule
    start_rule = find_global 'APLGrammar', 'prog'
    match = start_rule(source)

    # Verify the match
    $I0 = match.__get_bool()
    unless $I0 goto err_match_fail           # if match fails stop

=for debug

    print "parse succeeded\n"
    print "Match tree dump:\n"
    load_bytecode 'dumper.pir'
    load_bytecode 'PGE/Dumper.pir'
    $P0 = find_global '_dumper'
    $P0(match, '$/')

=cut

    # "Traverse" the parse tree
    .local pmc grammar
    grammar = new 'ASTGrammar'

    # Construct the "AST"
    .local pmc astbuilder
    astbuilder = grammar.apply(match)
    .local pmc ast
    ast = astbuilder.get('result')
    $I0 = defined ast
    unless $I0 goto err_no_ast # if AST fails stop

# print "\n\nAST tree dump:\n"
# ast.dump()

    # Compile the abstract syntax tree down to an opcode syntax tree
    .local pmc ostgrammar
    ostgrammar = new 'OSTGrammar'
    .local pmc ostbuilder
    ostbuilder = ostgrammar.apply(ast)
    .local pmc ost
    ost = ostbuilder.get('result')
    $I0 = defined ost
    unless $I0 goto err_no_ost # if OST fails stop

#    print "\n\nOST tree dump:\n"
#    ost.dump()

    # Compile the OST down to PIR
    .local pmc pirgrammar
    pirgrammar = new 'PIRGrammar'
    .local pmc pirbuilder
    pirbuilder = pirgrammar.apply(ost)
    .local pmc pir
    pir = pirbuilder.get('result')
    unless pir goto err_no_pir # if PIR not generated, stop

#    print "\n\nPIR dump:\n"
#    print pir

    # Execute
    .local pmc pir_compiler
    .local pmc pir_compiled
    pir_compiler = compreg "PIR"
    pir_compiled = pir_compiler( pir )

    pir_compiled()

    end

  err_match_fail:
    print "parse failed\n"
    goto cleanup

  err_no_ast:
    print "Unable to construct AST.\n"

  err_no_ost:
    print "Unable to construct OST.\n"

  err_no_pir:
    print "Unable to construct PIR.\n"

  cleanup:
    end
.end

# Read in the source from a file
.sub _get_source
    .param pmc argv
    .local string filename

    $I0 = argv
    if $I0 != 2 goto err_no_file

    # Read in the source file
    filename = argv[1]
    $S1 = _slurp_file(filename)
    .return ($S1)

  err_no_file:
    print "You must supply an APL file to parse.\n"
    end
.end

.sub _slurp_file
    .param string filename

    .local pmc filehandle
    filehandle = open filename, "<"
    unless filehandle goto err_no_file
    push filehandle, 'utf8'
    $S1 = read filehandle, 65535
    close filehandle
    .return ($S1)

  err_no_file:
    print "Unable to open file "
    print filename
    print "\n"
    end
.end

=head1 LICENSE

Copyright (c) 2005-2006 The Perl Foundation

This is free software; you may redistribute it and/or modify
it under the same terms as Parrot.

=cut
