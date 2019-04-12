package AG::Categories;

use 5.010;
use warnings;
use strict;
use utf8;
use Carp;

sub get {
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

1;
