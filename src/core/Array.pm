my class X::Item { ... };

class Array {
    # Has attributes and parent List declared in BOOTSTRAP.    

    method new(|) { 
        my Mu $args := nqp::p6argvmarray();
        nqp::shift($args);
        nqp::p6list($args, self.WHAT, Bool::True);
    }
    
    multi method at_pos(Array:D: $pos) is rw {
#?if jvm
        if nqp::istype($pos, Num) && nqp::isnanorinf($pos) {
#?endif
#?if !jvm
        if nqp::isnanorinf($pos) {
#?endif
            X::Item.new(aggregate => self, index => $pos).throw;
        }
        my int $p = nqp::unbox_i($pos.Int);
        my Mu $items := nqp::p6listitems(self);
        # hotpath check for element existence (RT #111848)
        nqp::existspos($items, $p)
              || nqp::getattr(self, List, '$!nextiter').defined
                  && self.exists($p)
          ?? nqp::atpos($items, $p)
          !! nqp::p6bindattrinvres(my $v, Scalar, '$!whence',
                 -> { nqp::bindpos($items, $p, $v) } )
    }
    multi method at_pos(Array:D: int $pos) is rw {
        my Mu $items := nqp::p6listitems(self);
        # hotpath check for element existence (RT #111848)
        nqp::existspos($items, $pos)
              || nqp::getattr(self, List, '$!nextiter').defined
                  && self.exists($pos)
          ?? nqp::atpos($items, $pos)
          !! nqp::p6bindattrinvres(my $v, Scalar, '$!whence',
                 -> { nqp::bindpos($items, $pos, $v) } )
    }

    proto method bind_pos(|) { * }
    multi method bind_pos($pos is copy, Mu \bindval) is rw {
        $pos = $pos.Int;
        self.gimme($pos + 1);
        nqp::bindpos(nqp::getattr(self, List, '$!items'), nqp::unbox_i($pos), bindval);
    }
    multi method bind_pos(int $pos, Mu \bindval) is rw {
        self.gimme($pos + 1);
        nqp::bindpos(nqp::getattr(self, List, '$!items'), $pos, bindval)
    }
    
    method delete(@array is rw: *@indices) {
        my $elems = @array.elems;
        my @result;
        for @indices -> $index {
            my $i = $index ~~ Callable
                        ?? $index($elems)
                        !! +$index;
            @result.push(@array[$i]);
            undefine @array[$i];

            # next seems unnecessary but handles an obscure
            # edge case
            if $i == (@array - 1) {
                @array.pop;
            }
        }
        @array.pop while ?@array && !defined @array[@array.elems - 1];
        return @result;
    }

    method flattens() { 1 }

    multi method perl(Array:D \SELF:) {
        nqp::iscont(SELF)
          ?? '[' ~ self.map({.perl}).join(', ') ~ ']'
          !! self.WHAT.perl ~ '.new(' ~ self.map({.perl}).join(', ') ~ ')'
    }

    method REIFY(Parcel \parcel, Mu \nextiter) {
        my Mu $rpa := nqp::getattr(parcel, Parcel, '$!storage');
        my Mu $iter := nqp::iterator($rpa);
        my int $i = 0;
        while $iter {
            nqp::bindpos($rpa, $i, my $v = nqp::shift($iter));
            $i = $i + 1;
        }
        nqp::findmethod(List, 'REIFY')(self, parcel, nextiter)
    }

    method STORE_AT_POS(\pos, Mu $v is copy) is rw {
        nqp::findmethod(List, 'STORE_AT_POS')(self, pos, $v);
    }

    method STORE(|) {
        # get arguments, shift off invocant
        my $args := nqp::p6argvmarray();
        nqp::shift($args);
        # make an array from them (we can't just use ourself for this,
        # or @a = @a will go terribly wrong); make it eager
        my $list := nqp::p6list($args, Array, Mu);
        nqp::bindattr($list, List, '$!flattens', True);
        $list.eager;
        # clear our items and set our next iterator to be one over
        # the array we just created
        nqp::bindattr(self, List, '$!items', Mu);
        nqp::bindattr(self, List, '$!nextiter', nqp::p6listiter(nqp::list($list), self));
        self
    }

    my role TypedArray[::TValue] does Positional[TValue] {
        multi method at_pos($pos is copy, TValue $v? is copy) is rw {
            $pos = $pos.Int;
            self.exists($pos)
              ?? nqp::atpos(nqp::getattr(self, List, '$!items'), nqp::unbox_i($pos))
              !! nqp::p6bindattrinvres($v, Scalar, '$!whence',
                     -> { nqp::bindpos(nqp::getattr(self, List, '$!items'), nqp::unbox_i($pos), $v) } )
        }
        multi method at_pos(int $pos, TValue $v? is copy) is rw {
            self.exists($pos)
              ?? nqp::atpos(nqp::getattr(self, List, '$!items'), $pos)
              !! nqp::p6bindattrinvres($v, Scalar, '$!whence',
                     -> { nqp::bindpos(nqp::getattr(self, List, '$!items'), $pos, $v) } )
        }
        multi method bind_pos($pos is copy, TValue \bindval) is rw {
            $pos = $pos.Int;
            self.gimme($pos + 1);
            nqp::bindpos(nqp::getattr(self, List, '$!items'), nqp::unbox_i($pos), bindval)
        }
        multi method bind_pos(int $pos, TValue \bindval) is rw {
            self.gimme($pos + 1);
            nqp::bindpos(nqp::getattr(self, List, '$!items'), $pos, bindval)
        }
        # XXX some methods to come here...
    }
    method PARAMETERIZE_TYPE(Mu $t) {
        self but TypedArray[$t.WHAT]
    }
}


sub circumfix:<[ ]>(*@elems) is rw { my $x = @elems.eager }
