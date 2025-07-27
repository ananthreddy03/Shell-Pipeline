#!/bin/bash

start_time=$(date +%s)
set -e

cd /home/ananth/Bioinformatics/Genomics-Pipeline
#Define the Directories
RAW_DATA_DIR="/home/ananth/Bioinformatics/Genomics-Pipeline/Data"
TRIMMED_DATA_DIR="./Trimmed_Data"
RESULTS_DIR="./Results"
DB_DIR="./k2_standard_8gb_20241228"
REPORT_FILE="${RESULTS_DIR}/standard8_report.txt"

echo "Creating the required directories"
mkdir -p $RAW_DATA_DIR $TRIMMED_DATA_DIR $RESULTS_DIR $RESULTS_DIR/QC $RESULTS_DIR/QC_Trimmed $RESULTS_DIR/MultiQC_Report
mkdir k2_standard_8gb_20241228 Data_Visualization
#QC with FastQC
echo "[1/10] [FastQC] - Initiating Quality check!"
fastqc ${RAW_DATA_DIR}/*.fastq -o ${RESULTS_DIR}/QC || { echo "FastQC failed!"; exit 1; }
echo "[1/10] [FastQC] - Initial Quality check completed successfully!"

#Trimming
echo "[2/10] [Trimmomatic] - Starting trimming and quality filtering!"
java -jar /usr/local/bin/trimmomatic-0.39.jar PE -threads 4 -phred33 \
  ${RAW_DATA_DIR}/Sample1_fwd.fastq ${RAW_DATA_DIR}/Sample1_bwd.fastq \
  ${TRIMMED_DATA_DIR}/Sample1_fwd_paired.fastq ${TRIMMED_DATA_DIR}/Sample1_fwd_unpaired.fastq \
  ${TRIMMED_DATA_DIR}/Sample1_bwd_paired.fastq ${TRIMMED_DATA_DIR}/Sample1_bwd_unpaired.fastq \
  TRAILING:10 || { echo "Trimmomatic failed!"; exit 1; }
echo "[2/10] [Trimmomatic] - Adapter trimming and quality filtering completed!"
    
#FastQc on Trimmed data
echo "[3/10] [FastQC] - Running Quality check on Trimmed Data!"
fastqc ${TRIMMED_DATA_DIR}/*.fastq -o ${RESULTS_DIR}/QC_Trimmed || { echo "FastQC on trimmed data failed!"; exit 1; }
echo "[3/10] [FastQC] - Quality check on Trimmed data completed successfully!"

#Mutliqc
echo "[4/10] [MultiQC] - Generating a Multiqc report!"
multiqc ${RESULTS_DIR}/QC_Trimmed -o ${RESULTS_DIR}/MultiQC_report 2>/dev/null -o Data/ || { echo "MultiQC failed!"; exit 1; }
echo "[4/10] - Comprehensive report generated successfully!" 

#Fastq-Join
echo "[5/10] [Fastq-Join] - Merging paired-end reads!"
fastq-join ${TRIMMED_DATA_DIR}/Sample1_fwd_paired.fastq ${TRIMMED_DATA_DIR}/Sample1_bwd_paired.fastq \
  -o ${TRIMMED_DATA_DIR}/sample_merged.%f || { echo "Fastq-join failed!"; exit 1; }
echo "[5/10] [Fastq-Join] - Paired-end reads successfully stitched!"
cd /home/ananth/Bioinformatics/Genomics-Pipeline/Trimmed_Data
mv sample_merged.joinf sample_merged.fastq
cd /home/ananth/Bioinformatics/Genomics-Pipeline



#Downloading Standard Kraken2 DB
#echo "[6/10] [Kraken2] - Downloading Standard Kraken2 database (capped@8GB) !"
#wget https://genome-idx.s3.amazonaws.com/kraken/k2_standard_08gb_20241228.tar.gz || { echo "Download failed!"; exit 1; }
#echo "[6/10] [Kraken2] - Database downloaded successfully!"

echo "[7/10] [Kraken2] - Extracting the Kraken2 database!"
tar -xvzf k2_standard_08gb_20241228.tar.gz -C /home/ananth/Bioinformatics/Genomics-Pipeline/k2_standard_8gb_20241228 || { echo "Extraction failed!"; exit 1; }
echo "[7/10] [Kraken2] - Database extracted successfully!"

#Run Kraken2
export KRAKEN2_DB_PATH=${DB_DIR}

echo "[8/10] [Kraken2] - Running Kraken2 classification!"
kraken2 --db $DB_DIR --threads 4 \
  --report ${RESULTS_DIR}/standard8_report.txt \
  --output ${RESULTS_DIR}/standard8_output.txt \
  ${TRIMMED_DATA_DIR}/sample_merged.fastq || { echo "Kraken2 classification failed!"; exit 1; }
echo "[8/10] [Kraken2] - Reads classified successfully!"
echo "[9/10] [Kraken2] - Classification Report and Output files generated successfully!"


#Pavian
echo "Launch Pavian for interactive visualization (open in browser)..."
sleep 15

echo "Cleaning up intermediate files"
rm -rf ${TRIMMED_DATA_DIR}/*_paired.fastq ${TRIMMED_DATA_DIR}/*_unpaired.fastq ${TRIMMED_DATA_DIR}/*.un1f ${TRIMMED_DATA_DIR}/*.un2f ${RESULTS_DIR}/standard8_output.txt
sleep 2 
echo "[10/10] [Clean-up] Intermediate files removed successfully!"
echo "All steps completed successfully! "



end_time=$(date +%s)
elapsed=$((end_time - start_time))

echo "The Pipeline has been successfully executed..!"
echo "$((elapsed / 60)) minutes and $((elapsed % 60)) seconds elapsed..!"
