#!/usr/bin/perl

use 5.010;
use warnings;
use strict;
use utf8;
use Carp;
use Encode qw(encode decode);

use FindBin;
use lib "$FindBin::Bin/";

use File::Slurp qw(read_file write_file);
use JSON qw(from_json);
use File::Basename;
use File::Copy;
use Digest::MD5 qw(md5_hex);

use MyLaTeXParser;
use MyLaTeXPrinter;
use MyLaTeX;

no if $] >= 5.018, warnings => "experimental::smartmatch";

sub msg {
    my $caller = ( caller 1 )[3] // '[no_caller]';

    print "$caller(): @_\n";
    return;
}

sub generate_geopoints {
    my $list = shift;

    return join "\n\n", map {
        sprintf "\\newcommand{\\geo%s}[1][]{ \\geopoint{%.7f}{%.7f}{%s}{\\ifthenelse{\\equal{#1}{}}{%s}{#1}}}", $_,
            $list->{$_}{latitude}, $list->{$_}{longtitude},
            $list->{$_}{altitude} // q{},
            $list->{$_}{name},
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

my %commands_map;

my @tex_route_lists;
while ( my ( $lname, $list ) = each %{ $global->{config}{lists} } ) {
    my @list_routes = grep {
        ( $list->{routes_filter} // sub {1} )->($_)
    } @{ $global->{routes} };

    my $route_template = decode( 'utf-8', read_file("$global->{config}{template_directory}/$list->{route_template}") );

    my $content = q{};
    foreach my $route (@list_routes) {
        my $description = decode( 'utf-8', read_file("$route->{path}/description.tex") );
        my $category = get_category( $global, $route->{category} );
        my $peaks = join q{, }, @{ $route->{peak} };

        my $uiaa = q{};
        if ( -f "$route->{path}/uiaa.svg" ) {
            $uiaa = pdf_of_png( $global, "$route->{path}/uiaa.svg" );
        }

        my $doc = "{
    $global->{regions}{$route->{region}}{tex_geopoints}

$route_template
}";

        $doc = MyLaTeXParser::parse( id => "List $lname, route '$route->{title}'", document => $doc );
        $doc = MyLaTeX::map_commands(
            list => $doc,
            map  => {
                routeTitle       => sub { MyLaTeX::text( $route->{title} ) },
                routePeak        => sub { MyLaTeX::text($peaks) },
                routeCategory    => sub { MyLaTeX::text($category) },
                routeType        => sub { MyLaTeX::text( $route->{type} ) },
                routeName        => sub { MyLaTeX::text( $route->{name} ) },
                routeRegionName  => sub { MyLaTeX::text( $global->{regions}{ $route->{region} }{name} ) },
                routeEquipment   => sub { MyLaTeX::text( $route->{equipment} ) },
                routeAuthors     => sub { MyLaTeX::text( join q{, }, sort @{ $route->{authors} } ) },
                routeDescription => sub { MyLaTeX::text($description) },
                routeUIAAPath    => sub { MyLaTeX::text($uiaa) },
            } );

        $content .= MyLaTeXPrinter::latex( document => $doc );
    }

    my $doc = MyLaTeXParser::parse( id => "List $lname", document => $content, error_context => 1000 );
    $commands_map{$lname} = sub { return @{$doc} };
    push @tex_route_lists, "\\newcommand{\\routeList$lname}[0]{$content}\n";
}

my $book = read_file( "$global->{config}{template_directory}/book.tex", binmode => ':utf8' );
$book = MyLaTeXParser::parse( document => $book );
$book = MyLaTeX::map_commands( list => $book, map => \%commands_map );

write_file( "$global->{config}{destination_directory}/book.tex", encode( 'utf-8', MyLaTeXPrinter::latex( document => $book ) ) );

system "cd "
    . ( quotemeta $global->{config}{destination_directory} )
    . "; makeglossaries book.glo; pdflatex -halt-on-error -file-line-error book.tex";
