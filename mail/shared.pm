package shared;

use strict;
use warnings;

use Scalar::Util qw(reftype refaddr blessed);
use threads::shared;

# Predeclarations for internal functions
my ($make_shared);

# Create a thread-shared clone of a complex data structure or object
sub shared_copy
{
    Carp::carp('@_: ', @_);
    if (@_ != 1) {
        require Carp;
        Carp::croak('Usage: shared_clone(REF)');
    }

    return $make_shared->(shift, {});
}


### Internal Functions ###

# Used by shared_clone() to recursively clone
#   a complex data structure or object
$make_shared = sub {
    my ($item, $cloned) = @_;

    Carp::carp('reftype=', reftype($item));
    # Just return the item if:
    # 1. Not a ref;
    # 2. Already shared; or
    # 3. Not running 'threads'.
    return $item if (! ref($item) || is_shared($item) || ! $threads::threads);

    # Check for previously cloned references
    #   (this takes care of circular refs as well)
    my $addr = refaddr($item);
    if (exists($cloned->{$addr})) {
        # Return the already existing clone
        return $cloned->{$addr};
    }

    # Make copies of array, hash and scalar refs and refs of refs
    my $copy;
    my $ref_type = reftype($item);

    # Copy an array ref
    if ($ref_type eq 'ARRAY') {
        Carp::carp('array=', "@$item");
        # Make empty shared array ref
        $copy = &share([]);
        # Add to clone checking hash
        $cloned->{$addr} = $copy;
        # Recursively copy and add contents
        push(@$copy, map { $make_shared->($_, $cloned) } @$item);
    }

    # Copy a hash ref
    elsif ($ref_type eq 'HASH') {
        Carp::carp('key=', keys(%{$item}), ' value=', values(%{$item}));
        # Make empty shared hash ref
        $copy = &share({});
        # Add to clone checking hash
        $cloned->{$addr} = $copy;
        # Recursively copy and add contents
        foreach my $key (keys(%{$item})) {
            $copy->{$key} = $make_shared->($item->{$key}, $cloned);
        }
    }

    # Copy a scalar ref
    elsif ($ref_type eq 'SCALAR') {
        $copy = \do{ my $scalar = $$item; };
        share($copy);
        # Add to clone checking hash
        $cloned->{$addr} = $copy;
    }

    # Copy of a ref of a ref
    elsif ($ref_type eq 'REF') {
        # Special handling for $x = \$x
        if ($addr == refaddr($$item)) {
            $copy = \$copy;
            share($copy);
            $cloned->{$addr} = $copy;
        } else {
            my $tmp;
            $copy = \$tmp;
            share($copy);
            # Add to clone checking hash
            $cloned->{$addr} = $copy;
            # Recursively copy and add contents
            $tmp = $make_shared->($$item, $cloned);
        }

    } elsif ($ref_type eq 'GLOB') {
        $copy = \do{ my $glob = $$item; };
        share($copy);
        # Add to clone checking hash
        $cloned->{$addr} = $copy;
    } else {
        require Carp;
        Carp::croak("Unsupported ref type: ", $ref_type);
    }

    # If input item is an object, then bless the copy into the same class
    if (my $class = blessed($item)) {
        bless($copy, $class);
    }

    # Clone READONLY flag
    if ($ref_type eq 'SCALAR') {
        if (Internals::SvREADONLY($$item)) {
            Internals::SvREADONLY($$copy, 1) if ($] >= 5.008003);
        }
    }
    if (Internals::SvREADONLY($item)) {
        Internals::SvREADONLY($copy, 1) if ($] >= 5.008003);
    }

    return $copy;
};

1;

__END__

