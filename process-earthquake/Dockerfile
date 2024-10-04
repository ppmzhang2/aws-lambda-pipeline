# Use an official AWS Lambda base image for Python 3.11
FROM public.ecr.aws/lambda/python:3.11

# Set the working directory to the Lambda task root
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy current directory contents into the container
COPY . ${LAMBDA_TASK_ROOT}

# Create a custom directory for DuckDB extensions
RUN mkdir -p /opt/.duckdb/extensions

ENV DUCKDB_EXT_DIR=/opt/.duckdb/extensions

# Install the required Python packages into the custom directory
RUN pip install --no-cache-dir -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

# Preinstall the httpfs extension by running DuckDB and downloading the
# extension into the custom directory
RUN python -c "import duckdb; \
con = duckdb.connect(); \
con.execute('SET extension_directory=\"/opt/.duckdb/extensions\";'); \
con.execute('INSTALL httpfs');"

# Specify the entry point for the Lambda function
CMD ["main.handler"]
