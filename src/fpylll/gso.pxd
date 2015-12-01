# -*- coding: utf-8 -*-

from integer_matrix cimport IntegerMatrix
from fpylll cimport mat_gso_core_t, fplll_type_t

cdef class MatGSO:
    cdef fplll_type_t _type
    cdef mat_gso_core_t _core

    cdef readonly IntegerMatrix B
    cdef readonly IntegerMatrix U
    cdef readonly IntegerMatrix UinvT
