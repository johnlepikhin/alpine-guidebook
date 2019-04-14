package AG::Config;

use 5.010;
use warnings;
use strict;
use utf8;
use Carp;
use File::Slurp qw(read_file);
use JSON qw(from_json);
use File::Basename;

no if $] >= 5.018, warnings => "experimental::smartmatch";

my %config_schema = (
    source_directory => {
        cmd_alters  => 1,
        default     => q{./regions},
        description => q{Source directory to get regions/routes list from},
        required    => 1,
    },
    template_directory => {
        cmd_alters  => 1,
        default     => undef,
        description => q{Path to template to be used},
        required    => 1,
    },
    destination_directory => {
        cmd_alters  => 1,
        default     => undef,
        description => q{Destination directory, where guidebook and all LaTeX files will be created},
        required    => 1,
    },
    lists => {
        cmd_alters => 0,
        default    => {
            all => {
                routes_filter  => sub {1},
                route_template => 'route-template1.tex',
            },
        },
        description => q{Configuration of the list. Only Perl code at the moment, sorry},
        required    => 1,
    },
    category_system => {
        cmd_alters  => 1,
        default     => q{russian},
        description => q{Difficulty grading system. Known values: 'english', 'french', 'german', 'russian'},
        required    => 1,
    },
);

sub show_help {
    print <<'END'
  config=/path/to/config.pl
    Path to configuration file. At least 'lists' must be defined, see example-config.pl

END
        ;
    foreach ( sort keys %config_schema ) {
        my $default = '[no default value]';
        if ( $config_schema{$_}{default} && ref $config_schema{$_}{default} eq q{} ) {
            $default = "default value: '$config_schema{$_}{default}'";
        }
        my $addition = '';
        if ( $config_schema{$_}{cmd_alters} ) {
            $addition .= "\n    Can be changed by command line argument: $_=new_value";
        }
        print <<"END"
  $_=...   $default
    $config_schema{$_}{description}$addition

END
    }

    return;
}

sub get_regions_list {
    my $config = shift;

    my %r;

REGION:
    foreach my $info_file ( glob "$config->{source_directory}/*/info.json" ) {
        my $info = eval { from_json( read_file($info_file), { utf8 => 1 } ) };
        if ( ! defined $info ) {
            croak "cannot read $info_file: $@";
        }

        foreach my $k (qw(name)) {
            if ( ! defined $info->{$k} ) {
                croak "required key '$k' is not defined in $info_file";
            }
        }

        $info->{info_file} = $info_file;
        $info->{region}    = ( split m{/}, $info_file )[-2];
        $info->{path}      = dirname $info_file;

        $r{ $info->{region} } = $info;
    }

    return \%r;
}

sub get_routes_list {
    my $config = shift;

    my @r;
ROUTE:
    foreach my $info_file ( glob "$config->{source_directory}/*/routes/*/info.json" ) {
        my $info = eval { from_json( read_file($info_file), { utf8 => 1 } ) };
        if ( ! defined $info ) {
            croak "cannot read $info_file: $@";
        }

        foreach my $k (qw(peak category name title)) {
            if ( ! defined $info->{$k} ) {
                croak "required key '$k' is not defined in $info_file";
            }
        }

        $info->{info_file} = $info_file;
        $info->{region}    = ( split m{/}, $info_file )[-4];
        $info->{path}      = dirname $info_file;
        push @r, $info;
    }

    return \@r;
}

sub init {
    if ( '-h' ~~ @ARGV || '--help' ~~ @ARGV || 'help' ~~ @ARGV || ! @ARGV ) {
        show_help();
        exit 0;
    }

    my $config;

    my %cmd_params = map {
        if (m{^([^=]+)=(.*)}) {
            ( $1, $2 );
        } else {
            ();
        }
    } @ARGV;

    foreach ( keys %config_schema ) {
        if ( defined $config_schema{$_}{default} ) {
            $config->{$_} = $config_schema{$_}{default};
        }
    }

    if ( exists $cmd_params{config} ) {
        my $result = eval {
            my $content     = read_file( $cmd_params{config} );
            my $read_config = eval $content;
            if ($@) {
                die $@;
            }
            foreach ( sort keys %{$read_config} ) {
                $config->{$_} = $read_config->{$_};
            }
            1;
        };
        if ( ! $result ) {
            croak "Cannot parse config '$cmd_params{config}': $@";
        }

        foreach ( sort keys %{$config} ) {
            if ( ! exists $config_schema{$_} ) {
                croak "Unexpected config parameter: '$_'";
            }
        }

        delete $cmd_params{config};
    }

    foreach ( sort keys %cmd_params ) {
        if ( ! exists $config_schema{$_} ) {
            croak "Unexpected command line parameter: '$_'";
        }
        if ( ! $config_schema{$_}{cmd_alters} ) {
            croak "Parameter '$_' cannot be altered by command line";
        }
        $config->{$_} = $cmd_params{$_};
    }

    foreach ( sort keys %config_schema ) {
        if ( $config_schema{$_}{required} && ! exists $config->{$_} ) {
            croak "Config parameter '$_' is required";
        }
    }

    my %global = (
        config  => $config,
        regions => get_regions_list($config),
        routes  => get_routes_list($config),
    );

    return \%global;
}

1;
