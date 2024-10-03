# Use an official AWS Lambda base image for Python 3.11
FROM public.ecr.aws/lambda/python:3.11

# Set the working directory to the Lambda task root
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy current directory contents into the container
COPY . ${LAMBDA_TASK_ROOT}

RUN pip install --no-cache-dir -r requirements.txt --target "${LAMBDA_TASK_ROOT}"

# Preinstall the httpfs extension by running DuckDB and downloading the extension
RUN python -c "import duckdb; duckdb.connect().execute('INSTALL httpfs;')"

# Specify the entry point for the Lambda function
CMD ["main.handler"]
