# -----------------------------------------------------------------------------
# Copyright (c) 2025, Oracle and/or its affiliates.
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
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# dataframe_pandas.py
#
# Shows how to use connection.fetch_df_all() and connection.fetch_df_batches()
# to create Pandas dataframes.
# -----------------------------------------------------------------------------

import pandas
import oracledb
import sample_env

# determine whether to use python-oracledb thin mode or thick mode
if not sample_env.get_is_thin():
    oracledb.init_oracle_client(lib_dir=sample_env.get_oracle_client())

connection = oracledb.connect(
    user=sample_env.get_main_user(),
    password=sample_env.get_main_password(),
    dsn=sample_env.get_connect_string(),
    params=sample_env.get_connect_params(),
)

SQL = "select id, name from SampleQueryTab order by id"

# Get an OracleDataFrame.
# Adjust arraysize to tune the query fetch performance
odf = connection.fetch_df_all(statement=SQL, arraysize=100)

# Get a Pandas DataFrame from the data.
df = pandas.api.interchange.from_dataframe(odf)

# Perform various Pandas operations on the DataFrame

print("Columns:")
print(df.columns)

print("\nDataframe description:")
print(df.describe())

print("\nLast three rows:")
print(df.tail(3))

print("\nTransform:")
print(df.T)

# -----------------------------------------------------------------------------

# An example of batch fetching
#
# Note that since this particular example ends up with all query rows being
# held in memory, it would be more efficient to use fetch_df_all() as shown
# above.

print("\nFetching in batches:")
df = pandas.DataFrame()

# Tune 'size' for your data set. Here it is small to show the batch fetch
# behavior on the sample table.
for odf in connection.fetch_df_batches(statement=SQL, size=10):
    df_b = pandas.api.interchange.from_dataframe(odf)
    print(f"Appending {df_b.shape[0]} rows")
    df = pandas.concat([df, df_b], ignore_index=True)

print("\nLast three rows:")
print(df.tail(3))
