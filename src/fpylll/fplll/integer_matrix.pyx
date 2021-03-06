# -*- coding: utf-8 -*-
"""
Dense matrices over the Integers.

.. moduleauthor:: Martin R. Albrecht <martinralbrecht+fpylll@googlemail.com>

"""

include "fpylll/config.pxi"

from cpython cimport PyIndex_Check
from cysignals.signals cimport sig_on, sig_off

from fplll cimport Matrix, MatrixRow, sqr_norm, Z_NR
from fpylll.util cimport preprocess_indices, check_int_type
from fpylll.io cimport assign_Z_NR_mpz, assign_mpz, mpz_get_python

from fplll cimport IntType, ZT_MPZ, ZT_LONG, ZZ_mat

import re
from math import log10, ceil, sqrt, floor

from decl cimport z_long, z_mpz
from fpylll.gmp.pylong cimport mpz_get_pyintlong
from fpylll.gmp.mpz cimport mpz_init, mpz_mod, mpz_fdiv_q_ui, mpz_clear, mpz_cmp, mpz_sub, mpz_set, mpz_set_si, mpz_get_si

cdef class IntegerMatrixRow:
    """
    A reference to a row in an integer matrix.
    """
    def __init__(self, IntegerMatrix M, int row):
        """Create a row reference.

        :param IntegerMatrix M: Integer matrix
        :param int row: row index

        Row references are immutable::

            >>> from fpylll import IntegerMatrix
            >>> A = IntegerMatrix(2, 3)
            >>> A[0,0] = 1; A[0,1] = 2; A[0,2] = 3
            >>> r = A[0]
            >>> r[0]
            1
            >>> r[0] = 1
            Traceback (most recent call last):
            ...
            TypeError: 'fpylll.fplll.integer_matrix.IntegerMatrixRow' object does not support item assignment

        """
        preprocess_indices(row, row, M.nrows, M.nrows)
        self.row = row
        self.m = M

    def __getitem__(self, int column):
        """Return entry at ``column``

        :param int column: integer offset

        """
        preprocess_indices(column, column, self.m._ncols(), self.m._ncols())

        if self.m._type == ZT_MPZ:
            return mpz_get_python(self.m._core.mpz[0][self.row][column].get_data())
        elif self.m._type == ZT_LONG:
            return self.m._core.long[0][self.row][column].get_data()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._m._type)

    def __str__(self):
        """
        String representation of this row.

        Example::

            >>> from fpylll import IntegerMatrix
            >>> A = IntegerMatrix(2, 3)
            >>> A[0,0] = 1; A[0,1] = 2; A[0,2] = 3
            >>> print(str(A[0]))
            (1, 2, 3)

        """
        cdef int i
        r = []
        for i in range(self.m._ncols()):
            t = self.m._get(self.row, i)
            r.append(str(t))
        return "(" + ", ".join(r) + ")"

    def __repr__(self):
        """
        Example::

            >>> from fpylll import IntegerMatrix
            >>> A = IntegerMatrix(2, 3)
            >>> A[0,0] = 1; A[0,1] = 2; A[0,2] = 3
            >>> print(repr(A[0]))  # doctest: +ELLIPSIS
            row 0 of <IntegerMatrix(2, 3) at 0x...>

        """
        return "row %d of %r"%(self.row, self.m)

    def __reduce__(self):
        """
        Make sure attempts at pickling raise an error until proper pickling is implemented.
        """
        raise NotImplementedError

    def __abs__(self):
        """Return ℓ_2 norm of this vector.

        Example::

            >>> A = IntegerMatrix.from_iterable(1, 3, [1,2,3])
            >>> A[0].norm()  # doctest: +ELLIPSIS
            3.74165...
            >>> 1*1 + 2*2 + 3*3
            14
            >>> from math import sqrt
            >>> sqrt(14)  # doctest: +ELLIPSIS
            3.74165...

        """
        cdef Z_NR[mpz_t] t_mpz
        cdef Z_NR[long] t_l

        # TODO: don't just use doubles
        if self.m._type == ZT_MPZ:
            sqr_norm[Z_NR[mpz_t]](t_mpz, self.m._core.mpz[0][self.row], self.m._ncols())
            return sqrt(t_mpz.get_d())
        elif self.m._type == ZT_LONG:
            sqr_norm[Z_NR[long]](t_l, self.m._core.long[0][self.row], self.m._ncols())
            return sqrt(t_l.get_d())
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._m._type)

    norm = __abs__

    def __len__(self):
        """
        Return vector length.

        Example::

            >>> A = IntegerMatrix.from_matrix([[1,2],[3,4]], 2, 2)
            >>> len(A[0])
            2

        """
        if self.m._type == ZT_MPZ:
            return self.m._core.mpz[0][self.row].size()
        elif self.m._type == ZT_LONG:
            return self.m._core.long[0][self.row].size()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self.m._type)

    def is_zero(self, int frm=0):
        """
        Return ``True`` if this vector consists of only zeros starting at index ``frm``

        Example::

            >>> A = IntegerMatrix.from_matrix([[1,0,0]])
            >>> A[0].is_zero()
            False
            >>> A[0].is_zero(1)
            True

        """
        if self.m._type == ZT_MPZ:
            return bool(self.m._core.mpz[0][self.row].is_zero(frm))
        elif self.m._type == ZT_LONG:
            return bool(self.m._core.long[0][self.row].is_zero(frm))
        else:
            raise RuntimeError("Integer type '%s' not understood."%self.m._type)

    def size_nz(self):
        """
        Index at which an all zero vector starts.

        Example::

            >>> A = IntegerMatrix.from_matrix([[0,2,3],[0,2,0],[0,0,0]])
            >>> A[0].size_nz()
            3
            >>> A[1].size_nz()
            2
            >>> A[2].size_nz()
            0

        """

        if self.m._type == ZT_MPZ:
            return self.m._core.mpz[0][self.row].size_nz()
        elif self.m._type == ZT_LONG:
            return self.m._core.long[0][self.row].size_nz()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self.m._type)

    def __iadd__(self, IntegerMatrixRow v):
        """
        In-place add row vector ``v``

        :param IntegerMatrixRow v: a row vector

        Example::

            >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
            >>> A[0] += A[1]
            >>> print(A[0])
            (3, 6)
            >>> v = A[0]
            >>> v += A[1]
            >>> print(A[0])
            (6, 10)

        """
        if self.m._type == ZT_MPZ:
            self.m._core.mpz[0][self.row].add(v.m._core.mpz[0][v.row])
        elif self.m._type == ZT_LONG:
            self.m._core.long[0][self.row].add(v.m._core.long[0][v.row])
        else:
            raise RuntimeError("Integer type '%s' not understood."%self.m._type)
        return self

    def __isub__(self, IntegerMatrixRow v):
        """
        In-place subtract row vector ``v``

        :param IntegerMatrixRow v: a row vector

        Example::

            >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
            >>> A[0] -= A[1]
            >>> print(A[0])
            (-3, -2)
            >>> v = A[0]
            >>> v -= A[1]
            >>> print(A[0])
            (-6, -6)

        """
        if self.m._type == ZT_MPZ:
            self.m._core.mpz[0][self.row].sub(v.m._core.mpz[0][v.row])
        elif self.m._type == ZT_LONG:
            self.m._core.long[0][self.row].sub(v.m._core.long[0][v.row])
        else:
            raise RuntimeError("Integer type '%s' not understood."%self.m._type)
        return self

    def addmul(self, IntegerMatrixRow v, x=1, int expo=0):
        """In-place add row vector ``2^expo ⋅ x ⋅ v``

        :param IntegerMatrixRow v: a row vector
        :param x: multiplier
        :param int expo: scaling exponent.

        Example::

            >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
            >>> A[0].addmul(A[1])
            >>> print(A[0])
            (3, 6)

            >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
            >>> A[0].addmul(A[1],x=0)
            >>> print(A[0])
            (0, 2)

            >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
            >>> A[0].addmul(A[1],x=1,expo=2)
            >>> print(A[0])
            (12, 18)

        """
        cdef Z_NR[mpz_t] x_mpz_
        cdef Z_NR[mpz_t] tmp_mpz
        cdef Z_NR[long] x_l_
        cdef Z_NR[long] tmp_l

        if self.m._type == ZT_MPZ:
            assign_Z_NR_mpz(x_mpz_, x)
            self.m._core.mpz[0][self.row].addmul_2exp(v.m._core.mpz[0][v.row], x_mpz_, expo, tmp_mpz)
        elif self.m._type == ZT_LONG:
            x_l_ = <long>x
            self.m._core.long[0][self.row].addmul_2exp(v.m._core.long[0][v.row], x_l_, expo, tmp_l)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self.m._type)
        return


cdef class IntegerMatrix:
    """
    Dense matrices over the Integers.
    """

    def __init__(self, arg0, arg1=None, int_type="mpz"):
        """Construct a new integer matrix

        :param arg0: number of rows ≥ 0 or matrix
        :param arg1: number of columns ≥ 0 or ``None``

        The default constructor takes the number of rows and columns::

            >>> from fpylll import IntegerMatrix
            >>> IntegerMatrix(10, 10) # doctest: +ELLIPSIS
            <IntegerMatrix(10, 10) at 0x...>

            >>> IntegerMatrix(10, 0) # doctest: +ELLIPSIS
            <IntegerMatrix(10, 0) at 0x...>

            >>> IntegerMatrix(-1,  0)
            Traceback (most recent call last):
            ...
            ValueError: Number of rows must be >0

        The default constructor is also a copy constructor::

            >>> A = IntegerMatrix(2, 2)
            >>> A[0,0] = 1
            >>> B = IntegerMatrix(A)
            >>> B[0,0]
            1
            >>> A[0,0] = 2
            >>> B[0,0]
            1

        """
        self._type = check_int_type(int_type)

        if PyIndex_Check(arg0) and PyIndex_Check(arg1):
            if arg0 < 0:
                raise ValueError("Number of rows must be >0")

            if arg1 < 0:
                raise ValueError("Number of columns must be >0")

            if self._type == ZT_MPZ:
                self._core.mpz = new ZZ_mat[mpz_t](arg0, arg1)
            elif self._type == ZT_LONG:
                self._core.long = new ZZ_mat[long](arg0, arg1)
            else:
                raise ValueError("Integer type '%s' not understood."%int_type)
            return

        elif isinstance(arg0, IntegerMatrix) and arg1 is None:
            if self._type == ZT_MPZ:
                self._core.mpz = new ZZ_mat[mpz_t](arg0.nrows, arg0.ncols)
            elif self._type == ZT_LONG:
                self._core.long = new ZZ_mat[long](arg0.nrows, arg0.ncols)
            else:
                raise ValueError("Integer type '%s' not understood."%int_type)

            self.set_matrix(arg0)
            return

        else:
            raise TypeError("Parameters arg0 and arg1 not understood")

    @classmethod
    def from_matrix(cls, A, nrows=None, ncols=None, **kwds):
        """Construct a new integer matrix from matrix-like object A

        :param A: a matrix like object, with element access A[i,j] or A[i][j]
        :param nrows: number of rows (optional)
        :param ncols: number of columns (optional)


        >>> A = IntegerMatrix.from_matrix([[1,2,3],[4,5,6]])
        >>> print(A)
        [ 1 2 3 ]
        [ 4 5 6 ]

        """
        cdef int m, n

        if nrows is None:
            if hasattr(A, "nrows"):
                nrows = A.nrows
            elif hasattr(A, "__len__"):
                nrows = len(A)
            else:
                raise ValueError("Cannot determine number of rows.")
            if not PyIndex_Check(nrows):
                if callable(nrows):
                    nrows = nrows()
                else:
                    raise ValueError("Cannot determine number of rows.")

        if ncols is None:
            if hasattr(A, "ncols"):
                ncols = A.ncols
            elif hasattr(A[0], "__len__"):
                ncols = len(A[0])
            else:
                raise ValueError("Cannot determine number of rows.")
            if not PyIndex_Check(ncols):
                if callable(ncols):
                    ncols = ncols()
                else:
                    raise ValueError("Cannot determine number of rows.")

        m = nrows
        n = ncols

        B = cls(m, n, **kwds)
        B.set_matrix(A)
        return B

    @classmethod
    def from_iterable(cls, nrows, ncols, it, **kwds):
        """Construct a new integer matrix from matrix-like object A

        :param nrows: number of rows
        :param ncols: number of columns
        :param it: an iterable of length at least ``nrows * ncols``

        >>> A = IntegerMatrix.from_iterable(2,3, [1,2,3,4,5,6])
        >>> print(A)
        [ 1 2 3 ]
        [ 4 5 6 ]

        """
        A = cls(nrows, ncols, **kwds)
        A.set_iterable(it)
        return A

    @classmethod
    def identity(cls, nrows, int_type="mpz"):
        """Construct a new identity matrix of dimension ``nrows × nrows``

        :param nrows: number of rows.

        >>> A = IntegerMatrix.identity(4)
        >>> print(A)
        [ 1 0 0 0 ]
        [ 0 1 0 0 ]
        [ 0 0 1 0 ]
        [ 0 0 0 1 ]

        """
        A = IntegerMatrix(nrows, nrows, int_type=int_type)
        A.gen_identity(nrows)
        return A

    @classmethod
    def random(cls, d, algorithm, int_type="mpz", **kwds):
        """
        Construct new random matrix.

        :param d: dominant size parameter, see below for details
        :param algorithm: type of matrix create, see below for details
        :param int_type: underlying integer type

        :returns: a random lattice basis

        Examples::

            >>> from fpylll import set_random_seed
            >>> set_random_seed(1337)

            >>> print(IntegerMatrix.random(10, "intrel", bits=100))
            [ 256463166861109549799341521970 1 0 0 0 0 0 0 0 0 0 ]
            [ 873207450444980568127200753712 0 1 0 0 0 0 0 0 0 0 ]
            [ 516416770023228805415484560020 0 0 1 0 0 0 0 0 0 0 ]
            [ 994525604022093635359952223251 0 0 0 1 0 0 0 0 0 0 ]
            [ 780641228987278628796386273758 0 0 0 0 1 0 0 0 0 0 ]
            [ 340097864333930124184854172929 0 0 0 0 0 1 0 0 0 0 ]
            [ 844948852837276759341122419576 0 0 0 0 0 0 1 0 0 0 ]
            [ 324772894317620180051644618459 0 0 0 0 0 0 0 1 0 0 ]
            [ 376229655695162649452550239601 0 0 0 0 0 0 0 0 1 0 ]
            [ 495116044692403918956390532457 0 0 0 0 0 0 0 0 0 1 ]

        ::

            >>> print(IntegerMatrix.random(10, "simdioph", bits=10, bits2=100))
            [ 1267650600228229401496703205376  707  806  537  912  911  788  822  187  170 ]
            [                               0 1024    0    0    0    0    0    0    0    0 ]
            [                               0    0 1024    0    0    0    0    0    0    0 ]
            [                               0    0    0 1024    0    0    0    0    0    0 ]
            [                               0    0    0    0 1024    0    0    0    0    0 ]
            [                               0    0    0    0    0 1024    0    0    0    0 ]
            [                               0    0    0    0    0    0 1024    0    0    0 ]
            [                               0    0    0    0    0    0    0 1024    0    0 ]
            [                               0    0    0    0    0    0    0    0 1024    0 ]
            [                               0    0    0    0    0    0    0    0    0 1024 ]


        ::

            >>> print(IntegerMatrix.random(10, "uniform", bits=10))
            [ 973  94 326 837  61 477 614 100 180 342 ]
            [ 496 824 519  44 718 219 583 322 587 747 ]
            [ 493 919 759 510 523 601 499 223 259 745 ]
            [  47 828 224 878 125  85 577 307 842 541 ]
            [  54 805 185 424 211 165 473 801 596 768 ]
            [ 201 709 292 882 253 126 291 232 696 587 ]
            [ 410 303 252 547 517 999  78 776 334 474 ]
            [ 512 818  30 657 589 894 426 140 212  98 ]
            [ 314 947 225 231 923 274 456 376 608 210 ]
            [  17 486 924 427 455 937 734 915 732 438 ]

        ::

            >>> print(IntegerMatrix.random(5, "ntrulike", q=127))
            [ 1 0 0 0 0 125  39  62  24   4 ]
            [ 0 1 0 0 0   4 125  39  62  24 ]
            [ 0 0 1 0 0  24   4 125  39  62 ]
            [ 0 0 0 1 0  62  24   4 125  39 ]
            [ 0 0 0 0 1  39  62  24   4 125 ]
            [ 0 0 0 0 0 127   0   0   0   0 ]
            [ 0 0 0 0 0   0 127   0   0   0 ]
            [ 0 0 0 0 0   0   0 127   0   0 ]
            [ 0 0 0 0 0   0   0   0 127   0 ]
            [ 0 0 0 0 0   0   0   0   0 127 ]

        ::

            >>> print(IntegerMatrix.random(5, "ntrulike2", q=127))
            [ 127   0   0   0   0 0 0 0 0 0 ]
            [   0 127   0   0   0 0 0 0 0 0 ]
            [   0   0 127   0   0 0 0 0 0 0 ]
            [   0   0   0 127   0 0 0 0 0 0 ]
            [   0   0   0   0 127 0 0 0 0 0 ]
            [  67   3  46  34 104 1 0 0 0 0 ]
            [ 104  67   3  46  34 0 1 0 0 0 ]
            [  34 104  67   3  46 0 0 1 0 0 ]
            [  46  34 104  67   3 0 0 0 1 0 ]
            [   3  46  34 104  67 0 0 0 0 1 ]

        ::

            >>> print(IntegerMatrix.random(10, "qary", k=8, q=127))
            [ 1 0 107 110  45  98  19  71  10  87 ]
            [ 0 1  79  63  62   8  33 126  32  33 ]
            [ 0 0 127   0   0   0   0   0   0   0 ]
            [ 0 0   0 127   0   0   0   0   0   0 ]
            [ 0 0   0   0 127   0   0   0   0   0 ]
            [ 0 0   0   0   0 127   0   0   0   0 ]
            [ 0 0   0   0   0   0 127   0   0   0 ]
            [ 0 0   0   0   0   0   0 127   0   0 ]
            [ 0 0   0   0   0   0   0   0 127   0 ]
            [ 0 0   0   0   0   0   0   0   0 127 ]

        ::

            >>> print(IntegerMatrix.random(10, "trg", alpha=0.99))
            [ 127027      0      0      0     0     0    0   0   0   0 ]
            [   -524  68055      0      0     0     0    0   0   0   0 ]
            [ -28001  25785  43896      0     0     0    0   0   0   0 ]
            [   4141  15090 -11328  28142     0     0    0   0   0   0 ]
            [  -9556   4411  10194  -7745  7687     0    0   0   0   0 ]
            [  22770 -11762  15511  -6888  1915 12850    0   0   0   0 ]
            [  11304  26857 -15251  -3005 -1178  2695 2196   0   0   0 ]
            [  49186 -25085  -9654 -10658  1601 -4043 1090 816   0   0 ]
            [ -36512  12331 -12834   9700 -1098 -3501  579  58 309   0 ]
            [ -48197  18158  14830 -10361 -1478 -4212 -383 -23   5 638 ]

        Available Algorithms:

            - ``"intrel"`` - (``bits`` = `b`) generate a knapsack like matrix of dimension `d ×
              (d+1)` and `b` bits: the i-th vector starts with a random integer of bit-length `≤ b`
              and the rest is the i-th canonical unit vector.

            - ``"simdioph"`` - (``bits`` = `b_1`, ``bits2`` = `b_2`) generate a `d × d` matrix of a
              form similar to that is involved when trying to find rational approximations to reals
              with the same small denominator. The first vector starts with a random integer of
              bit-length `≤ b_2` and continues with `d-1` independent integers of bit-lengths `≤
              b_1`; the i-th vector for `i>1` is the i-th canonical unit vector scaled by a factor
              `2^{b_1}`.

            - ``"uniform"`` - (``bits`` = `b`) - generate a `d × d` matrix whose entries are independent
              integers of bit-lengths `≤ b`.

            - ``"ntrulike"`` - (``bits`` = `b` or ``q``) generate a `2d × 2d` NTRU-like matrix. If
              ``bits`` is given, then it first samples an integer `q` of bit-length `≤ b`, whereas
              if ``q``, then it sets `q` to the provided value. Then it samples a uniform `h` in the
              ring `Z_q[x]/(x^n-1)`. It finally returns the 2 x 2 block matrix `[[I, rot(h)], [0,
              qI]]`, where each block is `d x d`, the first row of `rot(h)` is the coefficient
              vector of `h`, and the i-th row of `rot(h)` is the shift of the (i-1)-th (with last
              entry put back in first position), for all i>1.

            - ``ntrulike2"`` - (``bits`` = `b` or ``q``) as the previous option, except that the
              constructed matrix is `[[qI, 0], [rot(h), I]]`.

            - ``"qary"`` - (``bits`` = `b` or ``q``, ``k``) generate a `d × d` q-ary matrix with
              determinant `q^k`. If ``bits`` is given, then it first samples an integer `q` of
              bit-length `≤ b`; if ``q`` is provided, then set `q` to the provided value. It returns
              a `2 x 2` block matrix `[[qI, 0], [H, I]]`, where `H` is `k x (d-k)` and uniformly
              random modulo q. These bases correspond to the SIS/LWE q-ary lattices. Goldstein-Mayer
              lattices correspond to `k=1` and `q` prime.

            - ``"trg"`` - (``alpha``) generate a `d × d` lower-triangular matrix `B` with `B_{ii} =
              2^{(d-i+1)^\\alpha}` for all `i`, and `B_{ij}` is uniform between `-B_{jj}/2` and
              `B_{jj}/2` for all ``j<i`.

        :warning: The NTRU options above do *not* produce genuine NTRU lattice with an unusually
            short dense sublattice.

        :seealso: :func:`~IntegerMatrix.randomize`
        """
        if algorithm == "intrel":
            A = IntegerMatrix(d, d+1, int_type=int_type)
        elif algorithm == "simdioph":
            A = IntegerMatrix(d, d, int_type=int_type)
        elif algorithm == "uniform":
            A = IntegerMatrix(d, d, int_type=int_type)
        elif algorithm == "ntrulike":
            A = IntegerMatrix(2*d, 2*d, int_type=int_type)
        elif algorithm == "ntrulike2":
            A = IntegerMatrix(2*d, 2*d, int_type=int_type)
        elif algorithm == "qary":
            A = IntegerMatrix(d, d, int_type=int_type)
        elif algorithm == "trg":
            A = IntegerMatrix(d, d, int_type=int_type)
        else:
            raise ValueError("Algorithm '%s' unknown."%algorithm)
        A.randomize(algorithm, **kwds)
        return A

    def set_matrix(self, A):
        """Set this matrix from matrix-like object A.

        :param A: a matrix like object, with element access A[i,j] or A[i][j]

        Example::

            >>> z = [[1,2,3,4], [5,6,7,8], [9,10,11,12], [13,14,15,16]]
            >>> A = IntegerMatrix(4, 4)
            >>> A.set_matrix(z)
            >>> print(A)
            [  1  2  3  4 ]
            [  5  6  7  8 ]
            [  9 10 11 12 ]
            [ 13 14 15 16 ]


            >>> A = IntegerMatrix(3, 3)
            >>> A.set_matrix(z)
            >>> print(A)
            [ 1  2  3 ]
            [ 5  6  7 ]
            [ 9 10 11 ]

        .. warning:: entries starting from ``A[nrows, ncols]`` are ignored.

        """
        cdef int i, j
        cdef int m = self._nrows()
        cdef int n = self._ncols()

        try:
            for i in range(m):
                for j in range(n):
                    self._set(i, j, A[i, j])
        except TypeError:
            for i in range(m):
                for j in range(n):
                    self._set(i, j, A[i][j])

    def set_iterable(self, A):
        """Set this matrix from iterable A

        :param A: an iterable object such as a list or tuple

        EXAMPLE::

            >>> z = range(16)
            >>> A = IntegerMatrix(4, 4)
            >>> A.set_iterable(z)
            >>> print(A)
            [  0  1  2  3 ]
            [  4  5  6  7 ]
            [  8  9 10 11 ]
            [ 12 13 14 15 ]

            >>> A = IntegerMatrix(3, 3)
            >>> A.set_iterable(z)
            >>> print(A)
            [ 0 1 2 ]
            [ 3 4 5 ]
            [ 6 7 8 ]

        .. warning:: entries starting at ``A[nrows * ncols]`` are ignored.

        """
        cdef int i, j
        cdef int m = self._nrows()
        cdef int n = self._ncols()
        it = iter(A)

        for i in range(m):
            for j in range(n):
                self._set(i, j, next(it))

    def to_matrix(self, A):
        """Write this matrix to matrix-like object A

        :param A: a matrix like object, with element access A[i,j] or A[i][j]
        :returns: A

        Example::

            >>> from fpylll import set_random_seed
            >>> z = [[0 for _ in range(10)] for _ in range(10)]
            >>> A = IntegerMatrix.random(10, "qary", q=127, k=5)
            >>> _ = A.to_matrix(z)
            >>> z[0] == list(A[0])
            True

        """
        cdef int i, j
        cdef int m = self._nrows()
        cdef int n = self._ncols()

        try:
            for i in range(m):
                for j in range(n):
                    A[i, j] = self._get(i, j)
        except TypeError:
            for i in range(m):
                for j in range(n):
                    A[i][j] = self._get(i, j)
        return A

    def __dealloc__(self):
        """
        Delete integer matrix
        """
        if self._type == ZT_MPZ:
            del self._core.mpz
        elif self._type == ZT_LONG:
            del self._core.long

    def __repr__(self):
        """Short representation.

        """
        return "<IntegerMatrix(%d, %d) at %s>" % (
            self._nrows(), self._ncols(), hex(id(self)))

    def __str__(self):
        """Full string representation of this matrix.

        """
        cdef int i, j
        max_length = []
        for j in range(self._ncols()):
            max_length.append(1)
            for i in range(self._nrows()):
                value = self._get(i, j)
                if not value:
                    continue
                length = ceil(log10(abs(value)))
                length += int(ceil(log10(abs(value))) == floor(log10(abs(value))))
                # sign
                length += int(value < 0)
                if length > max_length[j]:
                    max_length[j] = int(length)

        r = []
        for i in range(self._nrows()):
            r.append(["["])
            for j in range(self._ncols()):
                r[-1].append(("%%%dd"%max_length[j])%self._get(i,j))
            r[-1].append("]")
            r[-1] = " ".join(r[-1])
        r = "\n".join(r)
        return r

    @property
    def int_type(self):
        """
        """
        if self._type == ZT_LONG:
            return "long"
        if self._type == ZT_MPZ:
            return "mpz"

        raise RuntimeError("Integer type '%s' not understood."%self._type)

    def __copy__(self):
        """Copy this matrix.
        """
        cdef IntegerMatrix A = IntegerMatrix(self._nrows(), self._ncols(), int_type=self.int_type)
        cdef int i, j
        for i in range(self._nrows()):
            for j in range(self._ncols()):
                A._set(i, j, self._get(i,j))
        return A

    def __reduce__(self):
        """Serialize this matrix

        >>> import pickle
        >>> A = IntegerMatrix.random(10, "uniform", bits=20)
        >>> pickle.loads(pickle.dumps(A)) == A
        True

        """
        cdef int i, j
        l = []
        if self._type == ZT_MPZ:
            for i in range(self._nrows()):
                for j in range(self._ncols()):
                    # mpz_get_pyintlong ensure pickles work between Sage & not-Sage
                    l.append(int(mpz_get_pyintlong(self._core.mpz[0][i][j].get_data())))
        elif self._type == ZT_LONG:
            for i in range(self._nrows()):
                for j in range(self._ncols()):
                    # mpz_get_pyintlong ensure pickles work between Sage & not-Sage
                    l.append(int(self._core.long[0][i][j].get_data()))
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

        return unpickle_IntegerMatrix, (self._nrows(), self._ncols(), l, self.int_type)

    cdef long _nrows(self):
        if self._type == ZT_MPZ:
            return self._core.mpz[0].get_rows()
        elif self._type == ZT_LONG:
            return self._core.long[0].get_rows()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    cdef long _ncols(self):
        if self._type == ZT_MPZ:
            return self._core.mpz[0].get_cols()
        elif self._type == ZT_LONG:
            return self._core.long[0].get_cols()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    @property
    def nrows(self):
        """Number of Rows

        :returns: number of rows

        >>> from fpylll import IntegerMatrix
        >>> IntegerMatrix(10, 10).nrows
        10

        """
        return self._nrows()

    @property
    def ncols(self):
        """Number of Columns

        :returns: number of columns

        >>> from fpylll import IntegerMatrix
        >>> IntegerMatrix(10, 10).ncols
        10

        """
        return self._ncols()

    cdef object _get(self, int i, int j):
        if self._type == ZT_MPZ:
            return mpz_get_python(self._core.mpz[0][i][j].get_data())
        elif self._type == ZT_LONG:
            return self._core.long[0][i][j].get_data()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def __getitem__(self, key):
        """Select a row or entry.

        :param key: an integer for the row, a tuple for row and column or a slice.
        :returns: a reference to a row or an integer depending on format of ``key``

        >>> from fpylll import IntegerMatrix
        >>> A = IntegerMatrix(10, 10)
        >>> A.gen_identity(10)
        >>> A[1,0]
        0

        >>> print(A[1])
        (0, 1, 0, 0, 0, 0, 0, 0, 0, 0)

        >>> print(A[0:2])
        [ 1 0 0 0 0 0 0 0 0 0 ]
        [ 0 1 0 0 0 0 0 0 0 0 ]

        """
        cdef int i = 0
        cdef int j = 0

        if isinstance(key, tuple):
            i, j = key
            preprocess_indices(i, j, self._nrows(), self._ncols())
            return self._get(i, j)
        elif isinstance(key, slice):
            key = range(*key.indices(self._nrows()))
            return self.submatrix(key, range(self._ncols()))
        elif PyIndex_Check(key):
            i = key
            preprocess_indices(i, i, self._nrows(), self._nrows())
            return IntegerMatrixRow(self, i)
        else:
            raise ValueError("Parameter '%s' not understood."%key)

    cdef int _set(self, int i, int j, value) except -1:
        cdef long tmp
        if self._type == ZT_MPZ:
            assign_Z_NR_mpz(self._core.mpz[0][i][j], value)
        elif self._type == ZT_LONG:
            tmp = value
            self._core.long[0][i][j] = tmp
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def __setitem__(self, key, value):
        """
        Assign value to index.

        :param key: a tuple of row and column indices
        :param value: an integer

        Example::

            >>> from fpylll import IntegerMatrix
            >>> A = IntegerMatrix(10, 10)
            >>> A.gen_identity(10)
            >>> A[1,0] = 2
            >>> A[1,0]
            2

        The notation ``A[i][j]`` is not supported.  This is because ``A[i]`` returns an object
        of type ``IntegerMatrixRow`` object which is immutable by design.  This is to avoid the
        user confusing such an object with a proper vector.::

            >>> A[1][0] = 2
            Traceback (most recent call last):
            ...
            TypeError: 'fpylll.fplll.integer_matrix.IntegerMatrixRow' object does not support item assignment

        """
        cdef int i = 0
        cdef int j = 0

        if isinstance(key, tuple):
            i, j = key
            preprocess_indices(i, j, self._nrows(), self._ncols())
            self._set(i, j, value)

        elif isinstance(key, int):
            i = key
            preprocess_indices(i, i, self._nrows(), self._nrows())
            if isinstance(value, IntegerMatrixRow) \
               and (<IntegerMatrixRow>value).row == i \
               and (<IntegerMatrixRow>value).m == self:
                pass
            else:
                raise NotImplementedError
        else:
            raise ValueError("Parameter '%s' not understood."%key)

    def randomize(self, algorithm, **kwds):
        """Randomize this matrix using ``algorithm``.

        :param algorithm: see :func:`~IntegerMatrix.random`

        :seealso: :func:`~IntegerMatrix.random`

        """
        if algorithm == "intrel":
            bits = int(kwds["bits"])
            sig_on()
            if self._type == ZT_MPZ:
                self._core.mpz.gen_intrel(bits)
            elif self._type == ZT_LONG:
                self._core.long.gen_intrel(bits)
            else:
                raise RuntimeError("Integer type '%s' not understood."%self._type)
            sig_off()

        elif algorithm == "simdioph":
            bits = int(kwds["bits"])
            bits2 = int(kwds["bits2"])
            sig_on()
            if self._type == ZT_MPZ:
                self._core.mpz.gen_simdioph(bits, bits2)
            elif self._type == ZT_LONG:
                self._core.long.gen_simdioph(bits, bits2)
            else:
                raise RuntimeError("Integer type '%s' not understood."%self._type)
            sig_off()

        elif algorithm == "uniform":
            bits = int(kwds["bits"])
            sig_on()
            if self._type == ZT_MPZ:
                self._core.mpz.gen_uniform(bits)
            elif self._type == ZT_LONG:
                self._core.long.gen_uniform(bits)
            else:
                raise RuntimeError("Integer type '%s' not understood."%self._type)
            sig_off()

        elif algorithm == "ntrulike":
            if "q" in kwds:
                q = int(kwds["q"])
                sig_on()
                if self._type == ZT_MPZ:
                    self._core.mpz.gen_ntrulike_withq(q)
                elif self._type == ZT_LONG:
                    self._core.long.gen_ntrulike_withq(q)
                else:
                    raise RuntimeError("Integer type '%s' not understood."%self._type)
                sig_off()
            elif "bits" in kwds:
                bits = int(kwds["bits"])
                sig_on()
                if self._type == ZT_MPZ:
                    self._core.mpz.gen_ntrulike(bits)
                elif self._type == ZT_LONG:
                    self._core.long.gen_ntrulike(bits)
                else:
                    raise RuntimeError("Integer type '%s' not understood."%self._type)
                sig_off()
            else:
                raise ValueError("Either 'q' or 'bits' is required.")

        elif algorithm == "ntrulike2":
            if "q" in kwds:
                q = int(kwds["q"])
                sig_on()
                if self._type == ZT_MPZ:
                    self._core.mpz.gen_ntrulike2_withq(q)
                elif self._type == ZT_LONG:
                    self._core.long.gen_ntrulike2_withq(q)
                else:
                    raise RuntimeError("Integer type '%s' not understood."%self._type)
                sig_off()
            elif "bits" in kwds:
                bits = int(kwds["bits"])
                sig_on()
                if self._type == ZT_MPZ:
                    self._core.mpz.gen_ntrulike2(bits)
                elif self._type == ZT_LONG:
                    self._core.long.gen_ntrulike2(bits)
                else:
                    raise RuntimeError("Integer type '%s' not understood."%self._type)
                sig_off()
            else:
                raise ValueError("Either 'q' or 'bits' is required.")

        elif algorithm == "qary":
            k = int(kwds["k"])
            if "q" in kwds:
                q = int(kwds["q"])
                sig_on()
                if self._type == ZT_MPZ:
                    self._core.mpz.gen_qary_withq(k, q)
                elif self._type == ZT_LONG:
                    self._core.long.gen_qary_withq(k, q)
                else:
                    raise RuntimeError("Integer type '%s' not understood."%self._type)
                sig_off()
            elif "bits" in kwds:
                bits = int(kwds["bits"])
                sig_on()
                if self._type == ZT_MPZ:
                    self._core.mpz.gen_qary_prime(k, bits)
                elif self._type == ZT_LONG:
                    self._core.long.gen_qary_prime(k, bits)
                else:
                    raise RuntimeError("Integer type '%s' not understood."%self._type)
                sig_off()
            else:
                raise ValueError("Either 'q' or 'bits' is required.")

        elif algorithm == "trg":
            alpha = float(kwds["alpha"])
            sig_on()
            if self._type == ZT_MPZ:
                self._core.mpz.gen_trg(alpha)
            elif self._type == ZT_LONG:
                self._core.long.gen_trg(alpha)
            else:
                raise RuntimeError("Integer type '%s' not understood."%self._type)
            sig_off()

        else:
            raise ValueError("Algorithm '%s' unknown."%algorithm)

    def gen_identity(self, int nrows):
        """Generate identity matrix.

        :param nrows: number of rows

        """
        if self._type == ZT_MPZ:
            self._core.mpz.gen_identity(nrows)
        elif self._type == ZT_LONG:
            self._core.long.gen_identity(nrows)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def clear(self):
        """


        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).clear()
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).clear()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def is_empty(self):
        """


        """
        if self._type == ZT_MPZ:
            return bool((<Matrix[Z_NR[mpz_t]]*>self._core.mpz).empty())
        elif self._type == ZT_LONG:
            return bool((<Matrix[Z_NR[long]]*>self._core.long).empty())
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def resize(self, int rows, int cols):
        """

        :param int rows:
        :param int cols:

        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).resize(rows, cols)
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).resize(rows, cols)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def set_rows(self, int rows):
        """

        :param int rows:

        """
        if self._type == ZT_MPZ:
            (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).set_rows(rows)
        elif self._type == ZT_LONG:
            (<Matrix[Z_NR[long]]*>self._core.long).set_rows(rows)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def set_cols(self, int cols):
        """

        :param int cols:

        """
        if self._type == ZT_MPZ:
            (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).set_cols(cols)
        elif self._type == ZT_LONG:
            (<Matrix[Z_NR[long]]*>self._core.long).set_cols(cols)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def swap_rows(self, int r1, int r2):
        """

        :param int r1:
        :param int r2:

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
        >>> A.swap_rows(0, 1)
        >>> print(A)
        [ 3 4 ]
        [ 0 2 ]


        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).swap_rows(r1, r2)
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).swap_rows(r1, r2)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def rotate_left(self, int first, int last):
        """Row permutation.

        ``(M[first],…,M[last])`` becomes ``(M[first+1],…,M[last],M[first])``

        :param int first:
        :param int last:

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])

        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).rotate_left(first, last)
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).rotate_left(first, last)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def rotate_right(self, int first, int last):
        """Row permutation.

        ``(M[first],…,M[last])`` becomes ``(M[last],M[first],…,M[last-1])``

        :param int first:
        :param int last:

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])

        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).rotate_right(first, last)
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).rotate_right(first, last)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def rotate(self, int first, int middle, int last):
        """
        Rotates the order of the elements in the range [first,last), in such a way that the element
        pointed by middle becomes the new first element.

        ``(M[first],…,M[middle-1],M[middle],M[last])`` becomes
        ``(M[middle],…,M[last],M[first],…,M[middle-1])``

        :param int first: first index
        :param int middle: new first index
        :param int last: last index (inclusive)

        >>> A = IntegerMatrix.from_matrix([[0,1,2],[3,4,5],[6,7,8]])
        >>> A.rotate(0,0,2)
        >>> print(A)
        [ 0 1 2 ]
        [ 3 4 5 ]
        [ 6 7 8 ]

        >>> A = IntegerMatrix.from_matrix([[0,1,2],[3,4,5],[6,7,8]])
        >>> A.rotate(0,2,2)
        >>> print(A)
        [ 6 7 8 ]
        [ 0 1 2 ]
        [ 3 4 5 ]

        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).rotate(first, middle, last)
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).rotate(first, middle, last)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def rotate_gram_left(self, int first, int last, int n_valid_rows):
        """
        Transformation needed to update the lower triangular Gram matrix when
        ``rotateLeft(first, last)`` is done on the basis of the lattice.

        :param int first:
        :param int last:
        :param int n_valid_rows:

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])

        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).rotate_gram_left(first, last, n_valid_rows)
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).rotate_gram_left(first, last, n_valid_rows)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def rotate_gram_right(self, int first, int last, int n_valid_rows):
        """
        Transformation needed to update the lower triangular Gram matrix when
        ``rotateRight(first, last)`` is done on the basis of the lattice.

        :param int first:
        :param int last:
        :param int n_valid_rows:

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])

        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).rotate_gram_right(first, last, n_valid_rows)
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).rotate_gram_right(first, last, n_valid_rows)
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)

    def transpose(self):
        """
        Transpose.

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
        >>> _ = A.transpose()
        >>> print(A)
        [ 0 3 ]
        [ 2 4 ]

        """
        if self._type == ZT_MPZ:
            (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).transpose()
        elif self._type == ZT_LONG:
            (<Matrix[Z_NR[long]]*>self._core.long).transpose()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)
        return self

    def get_max_exp(self):
        """

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,4]])
        >>> A.get_max_exp()
        3

        >>> A = IntegerMatrix.from_matrix([[0,2],[3,9]])
        >>> A.get_max_exp()
        4

        """
        if self._type == ZT_MPZ:
            return (<Matrix[Z_NR[mpz_t]]*>self._core.mpz).get_max_exp()
        elif self._type == ZT_LONG:
            return (<Matrix[Z_NR[long]]*>self._core.long).get_max_exp()
        else:
            raise RuntimeError("Integer type '%s' not understood."%self._type)



# Extensions

    def __mul__(IntegerMatrix A, IntegerMatrix B):
        """Naive matrix × matrix products.

        :param IntegerMatrix A: m × n integer matrix A
        :param IntegerMatrix B: n × k integer matrix B
        :returns: m × k integer matrix C = A × B

        >>> from fpylll import set_random_seed
        >>> set_random_seed(1337)
        >>> A = IntegerMatrix(2, 2)
        >>> A.randomize("uniform", bits=2)
        >>> print(A)
        [ 2 0 ]
        [ 1 3 ]

        >>> B = IntegerMatrix(2, 2)
        >>> B.randomize("uniform", bits=2)
        >>> print(B)
        [ 3 2 ]
        [ 3 3 ]

        >>> print(A*B)
        [  6  4 ]
        [ 12 11 ]

        >>> print(B*A)
        [ 8 6 ]
        [ 9 9 ]

        """
        if A.ncols != B.nrows:
            raise ValueError("Number of columns of A (%d) does not match number of rows of B (%d)"%(A.ncols, B.nrows))

        cdef IntegerMatrix res = IntegerMatrix(A.nrows, B.ncols)
        cdef int i, j
        for i in range(A.nrows):
            for j in range(B.ncols):
                tmp = res._get(i, j)
                for k in range(A.ncols):
                    tmp += A._get(i,k) * B._get(k, j)
                res._set(i, j, tmp)
        return res

    def __mod__(IntegerMatrix self, q):
        """Return A mod q.

        :param q: a modulus > 0

        """
        A = self.__copy__()
        A.mod(q)
        return A

    def mod(IntegerMatrix self, q, int start_row=0, int start_col=0, int stop_row=-1, int stop_col=-1):
        """Apply moduluar reduction modulo `q` to this matrix.

        :param q: modulus
        :param int start_row: starting row
        :param int start_col: starting column
        :param int stop_row: last row (excluding)
        :param int stop_col: last column (excluding)

        >>> A = IntegerMatrix(2, 2)
        >>> A[0,0] = 1001
        >>> A[1,0] = 13
        >>> A[0,1] = 102
        >>> print(A)
        [ 1001 102 ]
        [   13   0 ]

        >>> A.mod(10, start_row=1, start_col=0)
        >>> print(A)
        [ 1001 102 ]
        [    3   0 ]

        >>> A.mod(10)
        >>> print(A)
        [ 1 2 ]
        [ 3 0 ]

        >>> A = IntegerMatrix(2, 2)
        >>> A[0,0] = 1001
        >>> A[1,0] = 13
        >>> A[0,1] = 102
        >>> A.mod(10, stop_row=1)
        >>> print(A)
        [  1 2 ]
        [ 13 0 ]

        """
        preprocess_indices(start_row, start_col, self._nrows(), self._ncols())
        preprocess_indices(stop_row, stop_col, self._nrows()+1, self._ncols()+1)

        cdef mpz_t q_
        mpz_init(q_)
        try:
            assign_mpz(q_, q)
        except NotImplementedError, msg:
            mpz_clear(q_)
            raise NotImplementedError(msg)

        cdef mpz_t t1
        mpz_init(t1)
        cdef mpz_t t2
        mpz_init(t2)

        cdef mpz_t q2_
        mpz_init(q2_)
        mpz_fdiv_q_ui(q2_, q_, 2)

        cdef int i, j
        for i in range(self._nrows()):
            for j in range(self._ncols()):
                if self._type == ZT_MPZ:
                    mpz_set(t1, self._core.mpz[0][i][j].get_data())
                elif self._type == ZT_LONG:
                    mpz_set_si(t1, self._core.long[0][i][j].get_data())
                else:
                    raise RuntimeError("Integer type '%s' not understood."%self._type)

                if start_row <= i < stop_row and start_col <= i < stop_col:
                    mpz_mod(t2, t1, q_)
                    if mpz_cmp(t2, q2_) > 0:
                        mpz_sub(t2, t2, q_)
                    if self._type == ZT_MPZ:
                        self._core.mpz[0][i][j].set(t2)
                    elif self._type == ZT_LONG:
                        self._core.long[0][i][j] = mpz_get_si(t2)
                    else:
                        raise RuntimeError("Integer type '%s' not understood."%self._type)

        mpz_clear(q_)
        mpz_clear(q2_)
        mpz_clear(t1)
        mpz_clear(t2)

    def __richcmp__(IntegerMatrix self, IntegerMatrix other, int op):
        """Compare two matrices
        """
        cdef int i, j
        cdef a, b
        if op == 2 or op == 3:
            eq = True
            if self._nrows() != other.nrows:
                eq = False
            elif self._ncols() != other.ncols:
                eq = False
            for i in range(self._nrows()):
                if eq is False:
                    break
                for j in range(self._ncols()):
                    a = self._get(i, j)
                    b = other._get(i, j)
                    if a != b:
                        eq = False
                        break
        else:
            raise NotImplementedError("Only != and == are implemented for integer matrices.")
        if op == 2:
            return eq
        elif op == 3:
            return not eq

    def apply_transform(self, IntegerMatrix U, int start_row=0):
        """Apply transformation matrix ``U`` to this matrix starting at row ``start_row``.

        :param IntegerMatrix U: transformation matrix
        :param int start_row: start transformation in this row

        """
        cdef int i, j
        S = self.submatrix(start_row, 0, start_row + U.nrows, self._ncols())
        cdef IntegerMatrix B = U*S
        for i in range(B.nrows):
            for j in range(B.ncols):
                tmp = B._get(i, j)
                self._set(start_row+i, j, tmp)

    def submatrix(self, a, b, c=None, d=None):
        """Construct a new submatrix.

        :param a: either the index of the first row or an iterable of row indices
        :param b: either the index of the first column or an iterable of column indices
        :param c: the index of first excluded row (or ``None``)
        :param d: the index of first excluded column (or ``None``)
        :returns:
        :rtype:

        We illustrate the calling conventions of this function using a 10 x 10 matrix::

            >>> from fpylll import IntegerMatrix, set_random_seed
            >>> A = IntegerMatrix(10, 10)
            >>> set_random_seed(1337)
            >>> A.randomize("ntrulike", bits=22, q=4194319)
            >>> print(A)
            [ 1 0 0 0 0 3021421  752690 1522220 2972677  119630 ]
            [ 0 1 0 0 0  119630 3021421  752690 1522220 2972677 ]
            [ 0 0 1 0 0 2972677  119630 3021421  752690 1522220 ]
            [ 0 0 0 1 0 1522220 2972677  119630 3021421  752690 ]
            [ 0 0 0 0 1  752690 1522220 2972677  119630 3021421 ]
            [ 0 0 0 0 0 4194319       0       0       0       0 ]
            [ 0 0 0 0 0       0 4194319       0       0       0 ]
            [ 0 0 0 0 0       0       0 4194319       0       0 ]
            [ 0 0 0 0 0       0       0       0 4194319       0 ]
            [ 0 0 0 0 0       0       0       0       0 4194319 ]

        We can either specify start/stop rows and columns::

            >>> print(A.submatrix(0,0,2,8))
            [ 1 0 0 0 0 3021421  752690 1522220 ]
            [ 0 1 0 0 0  119630 3021421  752690 ]

        Or we can give lists of rows, columns explicitly::

            >>> print(A.submatrix([0,1,2],range(3,9)))
            [ 0 0 3021421  752690 1522220 2972677 ]
            [ 0 0  119630 3021421  752690 1522220 ]
            [ 0 0 2972677  119630 3021421  752690 ]

        """
        cdef int m = 0
        cdef int n = 0
        cdef int i, j, row, col

        if c is None and d is None:
            try:
                iter(a)
                rows = a
                iter(b)
                cols = b
            except TypeError:
                raise ValueError("Inputs to submatrix not understood.")
            it = iter(rows)
            try:
                while True:
                    next(it)
                    m += 1
            except StopIteration:
                pass

            it = iter(cols)
            try:
                while True:
                    next(it)
                    n += 1
            except StopIteration:
                pass

            A = IntegerMatrix(m, n)

            i = 0
            for row in iter(rows):
                j = 0
                for col in iter(cols):
                    preprocess_indices(row, col, self._nrows(), self._ncols())
                    A._set(i, j, self._get(row, col))
                    j += 1
                i += 1
            return A
        else:
            if c < 0:
                c %= self._nrows()
            if d < 0:
                d %= self._ncols()

            preprocess_indices(a, b, self._nrows(), self._ncols())
            preprocess_indices(c, d, self._nrows()+1, self._ncols()+1)

            if c < a:
                raise ValueError("Last row (%d) < first row (%d)"%(c, a))
            if d < b:
                raise ValueError("Last column (%d) < first column (%d)"%(d, b))
            i = 0
            m = c - a
            n = d - b
            A = IntegerMatrix(m, n)
            for row in range(a, c):
                j = 0
                for col in range(b, d):
                    A._set(i, j, self._get(row, col))
                    j += 1
                i += 1
            return A

    def multiply_left(self, v, start=0):
        """Return ``v*A'`` where ``A'`` is ``A`` reduced to ``len(v)`` rows starting at ``start``.

        :param v: a tuple-like object
        :param start: start in row ``start``
        """
        r = [0]*self._ncols()
        for i in range(len(v)):
            for j in range(self._ncols()):
                r[j] += v[i]*self._get(start+i, j)
        return tuple(r)

    @classmethod
    def from_file(cls, filename, **kwds):
        """Construct new matrix from file.

        >>> import tempfile
        >>> A = IntegerMatrix.random(10, "qary", k=5, bits=20)

        >>> fn = tempfile.mktemp()
        >>> fh = open(fn, "w")
        >>> _ = fh.write(str(A))
        >>> fh.close()

        >>> B = IntegerMatrix.from_file(fn)
        >>> A == B
        True

        :param filename: name of file to read from

        """
        A = cls(0, 0, **kwds)
        with open(filename, 'r') as fh:
            for i, line in enumerate(fh.readlines()):
                line = re.match("\[+([^\]]+) *\]", line)
                if line is None:
                    continue
                line = line.groups()[0]
                line = line.strip()
                line = [e for e in line.split(" ") if e != '']
                ncols = len(line)
                values = map(int, line)
                if (<IntegerMatrix>A)._type == ZT_MPZ:
                    (<IntegerMatrix>A)._core.mpz.set_rows(i+1)
                    (<IntegerMatrix>A)._core.mpz.set_cols(ncols)
                elif (<IntegerMatrix>A)._type == ZT_LONG:
                    (<IntegerMatrix>A)._core.long.set_rows(i+1)
                    (<IntegerMatrix>A)._core.long.set_cols(ncols)
                else:
                    raise RuntimeError("Integer type '%s' not understood."%(<IntegerMatrix>A)._type)

                for j, v in enumerate(values):
                    (<IntegerMatrix>A)._set(i, j, v)
        return A


def unpickle_IntegerMatrix(nrows, ncols, l, int_type="mpz"):
    """Deserialize an integer matrix.

    :param nrows: number of rows
    :param ncols: number of columns
    :param l: list of entries

    """
    return IntegerMatrix.from_iterable(nrows, ncols, l, int_type=int_type)
