r"""
Interface with bliss: graph (iso/auto)morphism

Implemented functions:

.. csv-table::
    :class: contentstable
    :widths: 30, 70
    :delim: |

    :meth:`automorphism_group` | Returns the automorphism group of the given (di)graph
    :meth:`canonical_form` | Computes a canonical certificate for the given (di) graph.

AUTHORS:

    - Jernej Azarija

"""

#*****************************************************************************
#       Copyright (C) 2015 Jernej Azarija
#       Copyright (C) 2015 Nathann Cohen <nathann.cohen@gail.com>
#       Copyright (C) 2018 Christian Stump <christian.stump@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#                  http://www.gnu.org/licenses/
#*****************************************************************************
import numpy
from operator import itemgetter

from cpython cimport PyObject
from libc.limits cimport LONG_MAX

cdef extern from "bliss/graph.hh" namespace "bliss":

    cdef cppclass Stats:
        pass

    cdef cppclass AbstractGraph:
        pass

    cdef cppclass Graph(AbstractGraph):
        Graph(const unsigned int)
        void add_edge(const unsigned int, const unsigned int)
        void find_automorphisms(Stats&, void (*)(void* , unsigned int,
                    const unsigned int*), void*)
        void change_color(const unsigned int, const unsigned int);
        const unsigned int* canonical_form(Stats&, void (*)(void*,unsigned int,
                    const unsigned int*), void*)

    cdef cppclass Digraph(AbstractGraph):

        Digraph(const unsigned int)
        void add_edge(const unsigned int, const unsigned int)
        void find_automorphisms(Stats&, void (*)(void* , unsigned int,
                    const unsigned int*), void*)
        void change_color(const unsigned int, const unsigned int);
        const unsigned int* canonical_form(Stats&, void (*)(void*,unsigned int,
                    const unsigned int*), void*)
        unsigned int get_hash()

cdef void add_gen(void *user_param, unsigned int n, const unsigned int *aut):
    r"""
    This function is called each time a new generator of the automorphism group
    is found.

    This function is used to append the new generators to a Python list. Its
    main job is to translate a permutation into dijoint cycles.

    INPUT:

    - ``user_param`` (``void *``) -- in the current implementation, it points
      toward a Python object which is a pair
      ``(list_of_current_generators,vert_to_integer_labelling)``.

    - ``n`` (int) -- number of points in the graph.

    - ``aut`` (int *) -- an automorphism of the graph.
    """
    cdef int tmp     = 0
    cdef int marker  = 0
    cdef int cur     = 0
    perm        = []
    done        = [False]*n

    gens, int_to_vertex = <object> <PyObject *> user_param

    while True:
        while cur < n and done[cur]:
            cur+=1
        if cur == n:
            break

        marker = tmp = cur
        cycle = [int_to_vertex[cur]]
        done[cur] = True

        while aut[tmp] != marker:
            tmp = aut[tmp]
            done[tmp] = True
            cycle.append(int_to_vertex[tmp])

        perm.append(tuple(cycle))
    gens.append(perm)

cdef void empty_hook(void *user_param , unsigned int n, const unsigned int *aut):
    return

#####################################################
# constucting bliss graphs from graphs
#####################################################

cdef Graph *bliss_graph(G, partition, vert2int, int2vert):
    r"""
    Return a bliss copy of a graph G

    INPUT:

    - ``G`` (a graph)

    - ``partition`` -- a partition of the vertex set.

    - ``vert2int, int2vert`` -- Two empty dictionaries. The entries of the
      dictionary are later set to record the labeling of our graph. They are
      taken as arguments to avoid technicalities of returning Python objects in
      Cython functions.
    """
    cdef Graph *g = new Graph(G.order())

    if g == NULL:
        raise MemoryError("Allocation Failed")

    for i,v in enumerate(G.vertices()):
        vert2int[v] = i
        int2vert[i] = v

    for x,y in G.edges(labels=False):
       g.add_edge(vert2int[x],vert2int[y])

    if partition:
        for i in xrange(1, len(partition)):
            for v in partition[i]:
                g.change_color(vert2int[v], i)
    return g

cdef Digraph *bliss_digraph(G, partition, vert2int, int2vert):
    r"""
    Return a bliss copy of a digraph G

    INPUT:

    - ``G`` (a digraph)

    - ``partition`` -- a partition of the vertex set.

    - ``vert2int, int2vert`` -- Two empty dictionaries. The entries of the
      dictionary are later set to record the labeling of our graph. They are
      taken as arguments to avoid technicalities of returning Python objects in
      Cython functions.
    """
    cdef Digraph *g = new Digraph(G.order())

    for i,v in enumerate(G.vertices()):
        vert2int[v] = i
        int2vert[i] = v

    if g == NULL:
        raise MemoryError("Allocation Failed")

    for x,y in G.edges(labels=False):
        g.add_edge(vert2int[x],vert2int[y])

    if partition:
        for i in xrange(1, len(partition)):
            for v in partition[i]:
                g.change_color(vert2int[v], i)
    return g

#####################################################
# constucting bliss graphs from edge lists
#####################################################

cdef Graph *bliss_graph_from_labelled_edges(int Vnr, int Lnr, list Vout, list Vin, list labels, list partition, bint verbose=False):
    r"""
    Return a bliss graph from the input data

    .. WARNING::

        the input is not checked for correctness, any wrong input will result in a segfault

    INPUT:

    - ``Vnr`` (number of vertices, such that the vertices are 0 ... Vnr-1)

    - ``Lnr`` (number of labels, such that the labels are 0 ... Lnr-1)

    - ``Vout`` (the list of vertices of outgoing edges)

    - ``Vin`` (the list of vertices of ingoing edges)

    - ``labels`` (the list of edge labels)

    - ``partition`` -- a partition of the vertex set
    """
    cdef Py_ssize_t i, j
    cdef int logLnr
    cdef str binrep
    cdef str ind

    cdef Graph *g
    cdef int x,y, lab

    if Lnr == 1:
        g = new Graph(Vnr)
        if g == NULL:
            raise MemoryError("Allocation Failed")
    else:
        logLnr = len(numpy.binary_repr(Lnr))
        g = new Graph(Vnr*logLnr)
        if g == NULL:
            raise MemoryError("Allocation Failed")
        for i from 0 <= i < Vnr:
            for j from 1 <= j < logLnr:
                g.add_edge((j-1)*Vnr+i,j*Vnr+i)
                if verbose:
                    print "edge init", ((j-1)*Vnr+i,j*Vnr+i)

    cdef int Enr = len(Vout)

    for i from 0 <= i < Enr:
        x   = Vout[i]
        y   = Vin[i]
        if Lnr == 1:
            lab = 0
        else:
            lab = labels[i]

        if lab != 0:
            lab = lab+1
            binrep = numpy.binary_repr(lab, logLnr)

            for j from 0 <= j < logLnr:
                ind = binrep[j]
                if ind == "1":
                    g.add_edge((logLnr-1-j)*Vnr+x,(logLnr-1-j)*Vnr+y)
                    if verbose:
                        print "edge", ((logLnr-1-j)*Vnr+x,(logLnr-1-j)*Vnr+y)
        else:
            g.add_edge(x,y)
            if verbose:
                print "edge unlab", (x,y)

    if not bool(partition):
        partition = [list(range(Vnr))]
    cdef Pnr = len(partition)
    for i from 0 <= i < Pnr:
        for v in partition[i]:
            if Lnr == 1:
                g.change_color(v, i)
                if verbose:
                    print "color",(v, i)
            else:
                for j from 0 <= j < logLnr:
                    g.change_color(j*Vnr+v, j*Pnr+i)
                    if verbose:
                        print "color",(j*Vnr+v, j*Pnr+i)
    return g

cdef Digraph *bliss_digraph_from_labelled_edges(int Vnr, int Lnr, list Vout, list Vin, list labels, list partition, bint verbose=False):
    r"""
    Return a bliss digraph from the input data

    .. WARNING::

        the input is not checked for correctness, any wrong input will result in a segfault

    INPUT:

    - ``Vnr`` (number of vertices, such that the vertices are 0 ... Vnr-1)

    - ``Lnr`` (number of labels, such that the labels are 0 ... Lnr-1)

    - ``Vout`` (the list of vertices of outgoing edges)

    - ``Vin`` (the list of vertices of ingoing edges)

    - ``labels`` (the list of edge labels)

    - ``partition`` -- a partition of the vertex set
    """
    cdef Py_ssize_t i, j
    cdef int logLnr
    cdef str binrep
    cdef str ind

    cdef Digraph *g
    cdef int x,y, lab

    if Lnr == 1:
        g = new Digraph(Vnr)
        if g == NULL:
            raise MemoryError("Allocation Failed")
    else:
        logLnr = len(numpy.binary_repr(Lnr))
        g = new Digraph(Vnr*logLnr)
        if g == NULL:
            raise MemoryError("Allocation Failed")
        for i from 0 <= i < Vnr:
            for j from 1 <= j < logLnr:
                g.add_edge((j-1)*Vnr+i,j*Vnr+i)
                if verbose:
                    print "edge init", ((j-1)*Vnr+i,j*Vnr+i)

    cdef int Enr = len(Vout)

    for i from 0 <= i < Enr:
        x   = Vout[i]
        y   = Vin[i]
        if Lnr == 1:
            lab = 0
        else:
            lab = labels[i]

        if lab != 0:
            lab = lab+1
            binrep = numpy.binary_repr(lab)

            for j from 0 <= j < logLnr:
                ind = binrep[j]
                if ind == "1":
                    g.add_edge((logLnr-1-j)*Vnr+x,(logLnr-1-j)*Vnr+y)
                    if verbose:
                        print "edge", ((logLnr-1-j)*Vnr+x,(logLnr-1-j)*Vnr+y)
        else:
            g.add_edge(x,y)
            if verbose:
                print "edge unlab", (x,y)

    if not bool(partition):
        partition = [list(range(Vnr))]
    cdef Pnr = len(partition)
    for i from 0 <= i < Pnr:
        for v in partition[i]:
            if Lnr == 1:
                g.change_color(v, i)
                if verbose:
                    print "color",(v, i)
            else:
                for j from 0 <= j < logLnr:
                    g.change_color(j*Vnr+v, j*Pnr+i)
                    if verbose:
                        print "color",(j*Vnr+v, j*Pnr+i)
    return g

#####################################################
# canonical form from graph or edge list
#####################################################

cpdef canonical_form(G, partition=None, return_graph=False, certificate=False):
    r"""
    Return the canonical label of ``G``.

    A canonical label ``canonical_form(G)`` of ``G`` is a (di)graph defined on
    `\{0,...,n-1\}` such that ``G`` is isomorphic to ``H`` if and only if
    ``canonical_form(G)`` is equal to ``canonical_form(H)``.

    INPUT:

    - ``G`` -- A graph or digraph.

    - ``partition`` -- A partition of the vertices of ``G`` into color classes.
      Defaults to ``None``.

    - ``return_graph`` -- If set to ``True``, ``canonical_form`` returns the
      canonical graph of ``G``. Otherwise, it returns its set of edges.

    - ``certificate`` -- If set to ``True`` returns the labeling of G into a
      canonical graph.

    TESTS::

        sage: from sage.graphs.bliss import canonical_form                  # optional - bliss
        sage: G = graphs.PetersenGraph()                                    # optional - bliss
        sage: canonical_form(G)                                             # optional - bliss
        [(2, 0, None),
         (2, 1, None),
         (3, 0, None),
         (4, 1, None),
         (5, 3, None),
         (5, 4, None),
         (6, 0, None),
         (6, 4, None),
         (7, 1, None),
         (7, 3, None),
         (8, 2, None),
         (8, 5, None),
         (9, 6, None),
         (9, 7, None),
         (9, 8, None)]

        sage: P = graphs.GeneralizedPetersenGraph(5,2)                      # optional - bliss
        sage: Q = graphs.PetersenGraph()                                    # optional - bliss
        sage: canonical_form(P) == canonical_form(Q)                        # optional - bliss
        True

        sage: canonical_form(Graph(15),return_graph=True)                   # optional - bliss
        Graph on 15 vertices
        sage: g = digraphs.RandomTournament(40)                             # optional - bliss
        sage: g.is_isomorphic(canonical_form(g,return_graph=True))          # optional - bliss
        True

        sage: g1 = graphs.RandomGNP(100,.4)                                 # optional - bliss
        sage: r = Permutations(range(100)).random_element()                 # optional - bliss
        sage: g2 = Graph([(r[u],r[v]) for u,v in g1.edges(labels=False)])   # optional - bliss
        sage: g1 = canonical_form(g1,return_graph=True)                     # optional - bliss
        sage: g2 = canonical_form(g2,return_graph=True)                     # optional - bliss
        sage: g2 == g2                                                      # optional - bliss
        True

        sage: g = Graph({1: [2]})
        sage: g_ = canonical_form(g, return_graph=True, certificate=True)    # optional - bliss
        sage: 0 in g_[0]                                                 # optional - bliss
        True
    """
    # We need this to convert the numbers from <unsigned int> to
    # <long>. This assertion should be true simply for memory reasons.
    cdef unsigned long Vnr = G.order()
    assert Vnr <= <unsigned long>LONG_MAX

    cdef bint directed = G.is_directed()

    cdef int labInd
    cdef list Vout   = []
    cdef list Vin    = []
    cdef list labels = []

    vert2int         = {}
    int2vert         = [None]*Vnr
    edge_labels      = []
    edge_labels_rev  = {}
    cdef int Lnr     = 0

    for i,v in enumerate(G.vertices()):
        vert2int[v] = i
        int2vert[i] = v

    for x,y,lab in G.edges(labels=True):
        try:
            labInd = edge_labels_rev[lab]
        except KeyError:
            labInd = Lnr
            Lnr    = Lnr+1
            edge_labels_rev[lab] = labInd
            edge_labels.append(lab)

        Vout.append(vert2int[x])
        Vin.append(vert2int[y])
        labels.append(labInd)

    lab_relabels = [ lab for _,lab in sorted(edge_labels_rev.iteritems(), key=itemgetter(0)) ]
    labels = [lab_relabels[i] for i in labels]
    new_edges, relabel = canonical_form_from_edge_list(Vnr, Vout, Vin, Lnr, labels, partition, directed, certificate=True)

    new_edges = [ (x,y,edge_labels[lab]) for x,y,lab in new_edges ]
    relabel = { int2vert[i]:j for i,j in relabel.iteritems() }

    if return_graph:
        if directed:
            from sage.graphs.graph import DiGraph
            G = DiGraph(new_edges,loops=G.allows_loops(),multiedges=G.allows_multiple_edges())
        else:
            from sage.graphs.graph import Graph
            G = Graph(new_edges,loops=G.allows_loops(),multiedges=G.allows_multiple_edges())

        G.add_vertices(vert2int.values())
        return (G, relabel) if certificate else G

    return (sorted(new_edges), relabel) if certificate else sorted(new_edges)

cpdef canonical_form_from_edge_list(int Vnr, list Vout, list Vin, int Lnr=1, list labels=[], list partition=None, bint directed=False, bint certificate=False):
    r"""
    Return an unsorted list of labelled edges of a canonical form.

    INPUT:

    - ``Vnr`` -- number of vertices such that the vertices are 0 ... Vnr-1

    - ``Vout`` -- the list of vertices of outgoing edges

    - ``Vin`` -- the list of vertices of ingoing edges

    - ``Lnr`` -- number of labels such that the labels are 0 ... Lnr-1

    - ``labels`` -- the list of edge labels)

    - ``partition`` -- a partition of the vertex set

    - ``directed`` -- boolean flag whether the edges are directed or not

    - ``certificate`` -- boolean flag whether to return the isomorphism to obtain the canonical labelling
    """
    # We need this to convert the numbers from <unsigned int> to
    # <long>. This assertion should be true simply for memory reasons.
    assert <unsigned long>(Vnr) <= <unsigned long>LONG_MAX

    cdef const unsigned int* aut
    cdef Graph* g
    cdef Digraph* d
    cdef Stats s
    cdef dict relabel

    cdef list new_edges = []
    cdef long e, f

    if directed:
        d = bliss_digraph_from_labelled_edges(Vnr, Lnr, Vout, Vin, labels, partition)
        aut = d.canonical_form(s, empty_hook, NULL)
    else:
        g = bliss_graph_from_labelled_edges(Vnr, Lnr, Vout, Vin, labels, partition)
        aut = g.canonical_form(s, empty_hook, NULL)

    for i from 0 <= i < len(Vout):
        x = Vout[i]
        y = Vin[i]
        e = aut[x]
        f = aut[y]
        if Lnr == 1:
            if not bool(labels):
                lab = None
            else:
                lab = labels[0]
            if directed:
                new_edges.append( (e,f,lab) )
            else:
                new_edges.append( (e,f,lab) if e > f else (f,e,lab))
        else:
            lab = labels[i]
            if directed:
                new_edges.append( (e,f,lab) )
            else:
                new_edges.append( (e,f,lab) if e > f else (f,e,lab))

    if certificate:
        relabel = {v: <long>aut[v] for v in range(Vnr)}

    if directed:
        del d
    else:
        del g

    if certificate:
        return new_edges, relabel
    else:
        return new_edges

#####################################################
# automorphism group from graphs
#####################################################

def automorphism_group(G, partition=None):
    """
    Computes the automorphism group of ``G`` subject to the coloring ``partition.``

    INPUT:

    - ``G`` -- A graph

    - ``partition`` -- A partition of the vertices of ``G`` into color classes.
      Defaults to ``None``, which is equivalent to a partition of size 1.

    TESTS::

        sage: from sage.graphs.bliss import automorphism_group                  # optional - bliss
        sage: G = graphs.PetersenGraph()                                        # optional - bliss
        sage: automorphism_group(G).is_isomorphic(G.automorphism_group())       # optional - bliss
        True

        sage: G = graphs.HeawoodGraph()                                         # optional - bliss
        sage: p = G.bipartite_sets()                                            # optional - bliss
        sage: A = G.automorphism_group(partition=[list(p[0]), list(p[1])])      # optional - bliss
        sage: automorphism_group(G, partition=p).is_isomorphic(A)               # optional - bliss
        True
    """

    cv = 0
    n = G.order()
    vert2int = {}
    int2vert = {}

    cdef Graph *g = NULL
    cdef Digraph *d = NULL
    cdef Stats s

    gens = []
    data = (gens, int2vert)

    if G.is_directed():
        d = bliss_digraph(G, partition, vert2int, int2vert)
        d.find_automorphisms(s, add_gen, <PyObject *> data)
        del d
    else:
        g = bliss_graph(G, partition, vert2int, int2vert)
        g.find_automorphisms(s, add_gen, <PyObject *> data)
        del g

    from sage.groups.perm_gps.permgroup import PermutationGroup
    return PermutationGroup(gens,domain=G)


