package MySyntax;

use warnings;
use strict;
use Carp qw(cluck croak confess);

use base 'Exporter';
our @EXPORT_OK = qw(get_arg get_arg_opt wrap_exn wrap_cb);

sub get_arg {
    my $name = shift;
    if ( ! defined $name ) {
        confess "'name' not passed to get_arg()";
    }
    if ( @_ % 2 ) {
        confess "Odd number of arguments for get_arg()";
    }

    my %args = @_;

    if ( ! exists $args{$name} ) {
        cluck "Argument '$name' is required";
        exit;
    } else {
        return $args{$name};
    }
}

sub get_arg_opt {
    my $name = shift;
    if ( ! defined $name ) {
        confess "'name' not passed to get_arg_opt()";
    }

    if ( ! @_ ) {
        confess "'default' not passed to get_arg_opt()";
    }
    my $default = shift;

    if ( @_ % 2 ) {
        confess "Odd number of arguments for get_arg_opt()";
    }
    my %args = @_;

    if ( ! exists $args{$name} ) {
        return $default;
    } else {
        return $args{$name};
    }
}

1;
