#!/usr/bin/perl

use 5.010;
use warnings;
use strict;
use utf8;
use Carp;
use Encode qw(encode decode);

use File::Slurp qw(read_file write_file);
use JSON qw(from_json);
use File::Basename;
use File::Copy;
use Digest::MD5 qw(md5_hex);

no if $] >= 5.018, warnings => "experimental::smartmatch";

sub msg {
    my $caller = ( caller 1 )[3] // '[no_caller]';

    print "$caller(): @_\n";
    return;
}

sub generate_geopoints {
    my $list = shift;

    return join "\n\n", map {
        sprintf "\\newcommand{\\geo%s}[1][]{
  \\geopoint{%.7f}{%.7f}{
    \\ifthenelse{\\equal{##1}{}}{$list->{$_}{name}}{##1}}}", $_, $list->{$_}{latitude}, $list->{$_}{longtitude}
    } keys %{$list};
}

sub get_regions_list {
    my $config = shift;

    my %r;

REGION:
    foreach my $info_file ( glob "$config->{source_directory}/*/info.json" ) {
        my $info = eval { from_json( read_file($info_file), { utf8 => 1 } ) };
        if ( ! defined $info ) {
            croak "cannot read $info_file: $@";
            next;
        }

        foreach my $k (qw(name)) {
            if ( ! defined $info->{$k} ) {
                croak "required key '$k' is not defined in $info_file";
                next REGION;
            }
        }

        $info->{info_file}     = $info_file;
        $info->{region}        = ( split m{/}, $info_file )[-2];
        $info->{path}          = dirname $info_file;
        $info->{tex_geopoints} = generate_geopoints( $info->{geopoints} // {} );

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
            next;
        }

        foreach my $k (qw(peak category name title)) {
            if ( ! defined $info->{$k} ) {
                croak "required key '$k' is not defined in $info_file";
                next ROUTE;
            }
        }

        $info->{info_file} = $info_file;
        $info->{region}    = ( split m{/}, $info_file )[-4];
        $info->{path}      = dirname $info_file;
        push @r, $info;
    }

    return \@r;
}

sub get_category {
    my $global   = shift;
    my $category = shift;

    if ( $global->{config}{category_system} eq 'russian' ) {
        return $category;
    }

    state $transition = {
        german => {
            '1Б' => 'L',
            '2А' => 'L/WS',
            '2Б' => 'WS',
            '3А' => 'WS/ZS',
            '3Б' => 'ZS',
            '4А' => 'ZS/S',
            '4Б' => 'S',
            '5А' => 'S',
            '5Б' => 'SS',
            '6А' => 'AS',
            '6Б' => 'EX',
        },
        french => {
            '1Б' => 'F',
            '2А' => 'PD-/PD',
            '2Б' => 'PD+',
            '3А' => 'AD-/AD',
            '3Б' => 'AD+',
            '4А' => 'D-/D',
            '4Б' => 'D+',
            '5А' => 'TD-',
            '5Б' => 'TD/TD+',
            '6А' => 'ED-/ED',
            '6Б' => 'ABO',
        },
        english => {
            '1Б' => 'F',
            '2А' => 'PD-/PD',
            '2Б' => 'PD+',
            '3А' => 'AD-/AD',
            '3Б' => 'AD+',
            '4А' => 'D-/D',
            '4Б' => 'D+',
            '5А' => 'TD-',
            '5Б' => 'TD/TD+',
            '6А' => 'ED1/ED2',
            '6Б' => 'ED2/ED3',
        },
    };

    return $transition->{ $global->{config}{category_system} }{$category} // "? (rus: $category)";
}

{
    my $images_dpi = 200;

    sub pdf_of_png {
        my $global = shift;
        my $svg    = shift;

        my $q_dpi   = quotemeta $images_dpi;
        my $q_svg   = quotemeta $svg;
        my $command = "inkscape -D -d $q_dpi -z $q_svg -e ";
        my $png     = "$global->{config}{destination_directory}/" . ( md5_hex $command) . ".png";
        if ( ! -e $png || ( stat $png )[9] < ( stat $svg )[9] ) {
            system $command . quotemeta $png;
        }

        return $png;
    }
}

{
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
        } );

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
}

binmode STDOUT, ':encoding(utf-8)';

my $global = init();

if ( ! -e $global->{config}{destination_directory} && ! mkdir $global->{config}{destination_directory} ) {
    croak "Cannot create destination direcotry: $!";
}

my @tex_route_lists;
while ( my ( $lname, $list ) = each %{ $global->{config}{lists} } ) {
    my @list_routes = grep {
        ( $list->{routes_filter} // sub {1} )->($_)
    } @{ $global->{routes} };
    my $route_template = decode( 'utf-8', read_file("$global->{config}{template_directory}/$list->{route_template}") );
## no critic (BuiltinFunctions::ProhibitComplexMappings)
    my $content = join "\n", map {
## use critic
        my $description = decode( 'utf-8', read_file("$_->{path}/description.tex") );
        my $category = get_category( $global, $_->{category} );
        my $peaks = join q{, }, @{ $_->{peak} };
        my $authors = join q{, }, sort @{ $_->{authors} // []};

        my $uiaa = '';
        if ( -f "$_->{path}/uiaa.svg" ) {
            $uiaa = pdf_of_png( $global, "$_->{path}/uiaa.svg" );
        }

        <<"END"

{
    $global->{regions}{$_->{region}}{tex_geopoints}
    \\newcommand{\\routeTitle}[0]{$_->{title}}
    \\newcommand{\\routePeak}[0]{$peaks}
    \\newcommand{\\routeCategory}[0]{$category}
    \\newcommand{\\routeType}[0]{$_->{type}}
    \\newcommand{\\routeName}[0]{$_->{name}}
    \\newcommand{\\routeRegionName}[0]{$global->{regions}{$_->{region}}{name}}
    \\newcommand{\\routeEquipment}[0]{$_->{equipment}}
    \\newcommand{\\routeDescription}[0]{$description}
    \\newcommand{\\routeUIAAPath}[0]{$uiaa}
    \\newcommand{\\routeAuthors}[0]{$authors}


    $route_template
}
END
            ;
    } @list_routes;

    push @tex_route_lists, "\\newcommand{\\routeList$lname}[0]{$content}\n";
}

write_file(
    "$global->{config}{destination_directory}/alpineroutes.sty",
    encode(
        'utf-8', <<"END"
\\NeedsTeXFormat{LaTeX2e}[1994/06/01]
\\ProvidesPackage{alpineroutes}[2019/03/23 Alpine Routes - autogenerated]

\\RequirePackage{xifthen}
\\RequirePackage{hyperref}

\\newcommand{\\geopoint}[3]{\\href{https://www.google.com/maps?q=#1,#2}{#3}}
\\newcommand{\\routeKey}[1]{\\textbf{#1}}

\\newcommand{\\routeSection}[2]{\\textbf{Section #1} #2}

\\newcommand{\\length}[1]{length #1m}

@tex_route_lists
END
    ) );

copy( "$global->{config}{template_directory}/book.tex", "$global->{config}{destination_directory}/book.tex" );
system "cd " . ( quotemeta $global->{config}{destination_directory} ) . "; pdflatex -halt-on-error -file-line-error book.tex";
