class Matrix(object):

    def __init__(self, n, m, data=None):
        self.n = n
        self.m = m

        self.rows = n * [None] # (n)
        for i in range(n):
            self.rows[i] = m * [None] # [m]

        if data is not None:
            assert len(data) == n * m, 'Wrong data shape'
            for i in range(len(data)):
                row = i // m
                col = i % m
                self.rows[row][col] = data[i]


class IdentityMatrix(Matrix):

    def __init__(self, size):
        Matrix.__init__(self, size, size, data=size*size*[0])
        for i in range(size):
            self.rows[i][i] = 1


def transpose(M):

    T = Matrix(M.m, M.n)

    for i in range(M.n * M.m):
        row = i // M.n
        col = i % M.n
        T.rows[row][col] = M.rows[col][row]

    return T


def simplemul(c, M):

    # Create result matrix
    res = Matrix(M.n, M.m)

    # Fill the matrix
    for i in range(res.n):
        for j in range(res.m):
            res.rows[i][j] = c * M.rows[i][j]

    return res


def matmul(A, B):

    # Check matrices shapes
    assert A.m == B.n, 'Matrices shape does not match'

    # Create result matrix
    res = Matrix(A.n, B.m)

    # Fill the matrix
    for i in range(res.n):
        for j in range(res.m):

            r = 0
            for a in range(A.m):
                r += A.rows[i][a] * B.rows[a][j]

            res.rows[i][j] = r

    return res


def matadd(A, B):

    # Check matrices shapes
    assert (A.n == B.n) & (A.m == B.m), 'Matrices shape does not match'

    # Create result matrix
    res = Matrix(A.n, B.m)

    # Fill the matrix
    for i in range(res.n):
        for j in range(res.m):
            res.rows[i][j] = A.rows[i][j] + B.rows[i][j]

    return res


def matsub(A, B):
    return matadd(A, simplemul(-1, B))