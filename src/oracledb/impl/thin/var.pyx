#------------------------------------------------------------------------------
# Copyright (c) 2020, 2025, Oracle and/or its affiliates.
#
# This software is dual-licensed to you under the Universal Permissive License
# (UPL) 1.0 as shown at https://oss.oracle.com/licenses/upl and Apache License
# 2.0 as shown at http://www.apache.org/licenses/LICENSE-2.0. You may choose
# either license.
#
# If you elect to accept the software under the Apache License, Version 2.0,
# the following applies:
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# var.pyx
#
# Cython file defining the variable implementation class (embedded in
# thin_impl.pyx).
#------------------------------------------------------------------------------

cdef class ThinVarImpl(BaseVarImpl):
    cdef:
        object _last_raw_value
        ArrowArrayImpl _last_arrow_array
        list _coroutine_indexes

    cdef int _bind(self, object conn, BaseCursorImpl cursor_impl,
                   uint32_t num_execs, object name, uint32_t pos) except -1:
        cdef:
            ThinCursorImpl thin_cursor_impl = <ThinCursorImpl> cursor_impl
            Statement stmt = thin_cursor_impl._statement
            object bind_info_dict = stmt._bind_info_dict
            list bind_info_list = stmt._bind_info_list
            OracleMetadata metadata = self.metadata
            ssize_t idx, num_binds, num_vars
            BindInfo bind_info
            str normalized_name
            bint is_async
            object value

        # for PL/SQL blocks, if the size of a string or bytes object exceeds
        # 32,767 bytes it must be converted to a BLOB/CLOB; an out converter
        # needs to be established as well to return the string in the way that
        # the user expects to get it
        if stmt._is_plsql and metadata.max_size > 32767:
            if metadata.dbtype._ora_type_num == ORA_TYPE_NUM_RAW \
                    or metadata.dbtype._ora_type_num == ORA_TYPE_NUM_LONG_RAW:
                metadata.dbtype = DB_TYPE_BLOB
            elif metadata.dbtype._csfrm == CS_FORM_NCHAR:
                metadata.dbtype = DB_TYPE_NCLOB
            else:
                metadata.dbtype = DB_TYPE_CLOB
            orig_converter = self.outconverter
            def converter(v):
                v = v.read()
                if orig_converter is not None:
                    v = orig_converter(v)
                return v
            self.outconverter = converter

        # for variables containing LOBs, create temporary LOBs, if needed
        is_async = thin_cursor_impl._conn_impl._protocol._transport._is_async
        if metadata.dbtype._ora_type_num == ORA_TYPE_NUM_CLOB \
                or metadata.dbtype._ora_type_num == ORA_TYPE_NUM_BLOB:
            for idx, value in enumerate(self._values):
                if value is not None \
                        and not isinstance(value, (PY_TYPE_LOB,
                                                   PY_TYPE_ASYNC_LOB)):
                    self._values[idx] = conn.createlob(metadata.dbtype, value)
                    if is_async:
                        if self._coroutine_indexes is None:
                            self._coroutine_indexes = []
                        self._coroutine_indexes.append(idx)

        # bind by name
        if name is not None:
            if name.startswith('"') and name.endswith('"'):
                normalized_name = name[1:-1]
            else:
                normalized_name = name.upper()
            if normalized_name.startswith(":"):
                normalized_name = normalized_name[1:]
            if normalized_name not in bind_info_dict:
                errors._raise_err(errors.ERR_INVALID_BIND_NAME, name=name)
            for bind_info in bind_info_dict[normalized_name]:
                stmt._set_var(bind_info, self, thin_cursor_impl)

        # bind by position
        else:
            num_binds = len(bind_info_list)
            num_vars = len(cursor_impl.bind_vars)
            if num_binds != num_vars:
                errors._raise_err(errors.ERR_WRONG_NUMBER_OF_POSITIONAL_BINDS,
                                  expected_num=num_binds, actual_num=num_vars)
            bind_info = bind_info_list[pos - 1]
            stmt._set_var(bind_info, self, thin_cursor_impl)

    cdef int _finalize_init(self) except -1:
        """
        Internal method that finalizes initialization of the variable.
        """
        BaseVarImpl._finalize_init(self)
        self._values = [None] * self.num_elements

    cdef ArrowArrayImpl _finish_building_arrow_array(self):
        """
        Finish building the Arrow array associated with the variable and then
        return that array (after clearing it in the variable so that a new
        array will be built if more rows are fetched). In thin mode, the
        duplicate row handling requires the last array to be retained, so do
        that here.
        """
        self._last_arrow_array = BaseVarImpl._finish_building_arrow_array(self)
        return self._last_arrow_array

    cdef list _get_array_value(self):
        """
        Internal method to return the value of the array.
        """
        return self._values[:self.num_elements_in_array]

    cdef object _get_scalar_value(self, uint32_t pos):
        """
        Internal method to return the value of the variable at the given
        position.
        """
        return self._values[pos]

    @cython.boundscheck(False)
    @cython.wraparound(False)
    cdef int _set_scalar_value(self, uint32_t pos, object value) except -1:
        """
        Set the value of the variable at the given position. At this point it
        is assumed that all checks have been performed!
        """
        self._values[pos] = value
