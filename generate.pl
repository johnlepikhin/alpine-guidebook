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

    return join "\n",
        map { "\\newcommand{\\geo$_}[0]{\\geopoint{$list->{$_}{latitude}}{$list->{$_}{longtitude}}{$list->{$_}{name}}}" } keys %{$list};
}

sub get_regions_list {
    my $global = shift;

    my %r;

REGION:
    foreach my $info_file ( glob "$global->{source_directory}/*/info.json" ) {
        my $info = eval { from_json( read_file($info_file), { utf8 => 1 } ) };
        if ( ! defined $info ) {
            msg "WARN: cannot read $info_file: $@";
            next;
        }

        foreach my $k (qw(name)) {
            if ( ! defined $info->{$k} ) {
                msg "WARN: required key '$k' is not defined in $info_file, skip this region";
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
            msg "WARN: cannot read $info_file: $@";
            next;
        }

        foreach my $k (qw(peak category name)) {
            if ( ! defined $info->{$k} ) {
                msg "WARN: required key '$k' is not defined in $info_file, skip this route";
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
    category_system => 'german',
);

my $regions = get_regions_list( \%global );

my @routes = get_routes_list( \%global );
msg "Found routes: ";
foreach (@routes) {
    msg " - $_->{region} : $_->{category} $_->{name} to $_->{peak}";
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
        <<"END"

{
    $regions->{$_->{region}}{tex_geopoints}
    \\newcommand{\\routePeak}[0]{$_->{peak}}
    \\newcommand{\\routeCategory}[0]{$category}
    \\newcommand{\\routeType}[0]{$_->{type}}
    \\newcommand{\\routeName}[0]{$_->{name}}
    \\newcommand{\\routeRegion}[0]{$_->{region}}
    \\newcommand{\\routeEquipment}[0]{$_->{equipment}}
    \\newcommand{\\routeDescription}[0]{$description}


    $route_template
}
END
            ;
    } @list_routes;

    push @tex_route_lists, "\\newcommand{\\routeList$lname}[0]{$content}\n";
}

write_file(
    "$global{destination_directory}/generated.tex",
    encode(
        'utf-8', <<"END"

@tex_route_lists
END
    ) );

copy( "$global{template_directory}/book.tex", "$global{destination_directory}/book.tex" );
system "cd " . ( quotemeta $global{destination_directory} ) . "; pdflatex book.tex";
