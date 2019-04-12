package MyLaTeX;

use warnings;
use strict;

use MySyntax qw(get_arg get_arg_opt);

sub text {
    return { type => 'TEXT', content => $_[0] };
}

sub command {
    my $command = get_arg command => @_;
    my $opts = get_arg_opt opts => undef, @_;
    my $args = get_arg_opt args => undef, @_;

    return {
        type    => 'COMMAND',
        command => $command,
        opts    => $opts,
        args    => $args,
    };
}

sub map_commands {
    my $map  = get_arg map  => @_;
    my $list = get_arg list => @_;
    my %args = @_;

    my $mapper = sub {
        my $node = $_;

        if ( $node->{type} eq 'GROUP' ) {
            $node->{children} = map_commands( %args, list => $node->{children} );
        }

        if ( $node->{type} eq 'COMMAND') {
            if (exists $map->{ $node->{command} } ) {
                return $map->{ $node->{command} }($node);
            }
            foreach ( @{ $node->{args} } ) {
                $_->{content} = map_commands( %args, list => $_->{content} );
            }
        }

        return $node;
    };

    return [ map { $mapper->($_) } @{$list} ];
}

1;
