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

sub msg {
    my $caller = ( caller 1 )[3] // '[no_caller]';

    print "$caller(): @_\n";
    return;
}

sub generate_geopoints {
    my $global = shift;
    my $list   = shift;

    return join "\n\n", map {
        "\\newcommand{\\geo$_}[1][]{
  \\geopoint{$list->{$_}{latitude}}{$list->{$_}{longtitude}}{
    \\ifthenelse{\\equal{##1}{}}{$list->{$_}{name}}{##1}
  }
}"
    } keys %{$list};
}

sub get_regions_list {
    my $global = shift;

    my %r;

REGION:
    foreach my $info_file ( glob "$global->{source_directory}/*/info.json" ) {
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
        $info->{tex_geopoints} = generate_geopoints( $global, $info->{geopoints} // {} );

        $r{ $info->{region} } = $info;
    }

    return \%r;
}

sub get_routes_list {
    my $global = shift;

    my @r;
ROUTE:
    foreach my $info_file ( glob "$global->{source_directory}/*/routes/*/info.json" ) {
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

    return @r;
}

sub get_category {
    my $global   = shift;
    my $category = shift;

    if ($global->{category_system} eq 'russian') {
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

    return $transition->{ $global->{category_system} }{$category} // "? (rus: $category)";
}

{
    my $id = 0;

    sub pdf_of_png {
        my $global = shift;
        my $svg    = shift;

        my $png = qq{$global->{destination_directory}/generated${id}.png};
        if (! -e $png || (stat $png)[9] < (stat $svg)[9]) {
            system 'inkscape', '-D', '-d', '400', '-z', $svg, '-e', $png;
        }
        $id++;

        return $png;
    }
}

binmode STDOUT, ':encoding(utf-8)';

my %global = (
    source_directory      => q{./regions},
    destination_directory => '/tmp/book',
    template_directory    => './templates/template1',
    lists                 => {
        all => {
            routes_filter  => sub {1},
            route_template => 'route-template1.tex',
        },
    },
    category_system => 'russian',
);

my $regions = get_regions_list( \%global );

my @routes = get_routes_list( \%global );
msg "Found routes: ";
foreach (@routes) {
    msg " - $_->{region} : $_->{category} $_->{title}";
}

mkdir $global{destination_directory};

my @tex_route_lists;
while ( my ( $lname, $list ) = each %{ $global{lists} } ) {
    my @list_routes = grep {
        ( $list->{routes_filter} // sub {1} )->($_)
    } @routes;
    my $route_template = decode( 'utf-8', read_file("$global{template_directory}/$list->{route_template}") );
## no critic (BuiltinFunctions::ProhibitComplexMappings)
    my $content = join "\n", map {
## use critic
        my $description = decode( 'utf-8', read_file("$_->{path}/description.tex") );
        my $category = get_category( \%global, $_->{category} );
        my $peaks = join q{, }, @{ $_->{peak} };

        my $uiaa = '';
        if ( -f "$_->{path}/uiaa.svg" ) {
            $uiaa = pdf_of_png( \%global, "$_->{path}/uiaa.svg" );
        }

        <<"END"

{
    $regions->{$_->{region}}{tex_geopoints}
    \\newcommand{\\routeTitle}[0]{$_->{title}}
    \\newcommand{\\routePeak}[0]{$peaks}
    \\newcommand{\\routeCategory}[0]{$category}
    \\newcommand{\\routeType}[0]{$_->{type}}
    \\newcommand{\\routeName}[0]{$_->{name}}
    \\newcommand{\\routeRegionName}[0]{$regions->{$_->{region}}{name}}
    \\newcommand{\\routeEquipment}[0]{$_->{equipment}}
    \\newcommand{\\routeDescription}[0]{$description}
    \\newcommand{\\routeUIAAPath}[0]{$uiaa}


    $route_template
}
END
            ;
    } @list_routes;

    push @tex_route_lists, "\\newcommand{\\routeList$lname}[0]{$content}\n";
}

write_file(
    "$global{destination_directory}/alpineroutes.sty",
    encode(
        'utf-8', <<"END"
\\NeedsTeXFormat{LaTeX2e}[1994/06/01]
\\ProvidesPackage{alpineroutes}[2019/03/23 Alpine Routes - autogenerated]

\\RequirePackage{xifthen}
\\RequirePackage{hyperref}

\\newcommand{\\geopoint}[3]{\\href{https://www.google.com/maps?q=#1,#2}{#3}}
\\newcommand{\\routeKey}[1]{\\textbf{#1}}

@tex_route_lists
END
    ) );

copy( "$global{template_directory}/book.tex", "$global{destination_directory}/book.tex" );
system "cd " . ( quotemeta $global{destination_directory} ) . "; pdflatex -file-line-error book.tex";
