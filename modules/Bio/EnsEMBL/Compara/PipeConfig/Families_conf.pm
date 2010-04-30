## Configuration file for the MCL family pipeline (development in progress)
#
# Don't forget to use '-lifespan 1200' on the beekeeper, otherwise the benefit of using the long queue will be lost.
# 
# rel.57+:  init_pipeline.pl execution took 8m45;   pipeline execution took 100hours (4.2 x days-and-nights) including queue waiting
# rel.58:   init_pipeline.pl execution took 5m (Albert's pipeline not working) or 50m (Albert's pipeline working);   pipeline execution took ...
#
# Note: in rel.57+ family_idmap analysis failed 4 times as part of pipeline, but ran successfully as via runWorker.pl
#
# FIXME!: in rel.58 because of some asynchronization between the NCBI taxonomy used by Uniprot and NCBI taxonomy loaded by Albert,
#   21 Uniprot member were loaded that didn't have a matching taxon_id in the database. It was only noticed after the pipeline has completed,
#   so the following removing queries had to be run:
#       DELETE member, family_member FROM member JOIN family_member USING (member_id) LEFT JOIN ncbi_taxa_name ON member.taxon_id = ncbi_taxa_name.taxon_id WHERE ncbi_taxa_name.taxon_id iS NULL;
#       DELETE family FROM family LEFT JOIN family_member ON family.family_id = family_member.family_id WHERE family_member.family_id iS NULL;
#   Instead of this, next time the offending members will have to be removed right after loading using LoadUniProt.pm runnable, before clusterization takes place.

#
## Please remember that mapping_session, stable_id_history, member and sequence tables will have to be MERGED in an intelligent way, and not just written over.
#

package Bio::EnsEMBL::Compara::PipeConfig::Families_conf;

use strict;
use warnings;
use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

sub default_options {
    my ($self) = @_;
    return {
        release        => '58',
        rel_suffix     => '',    # an empty string by default, a letter otherwise

        email          => $ENV{'USER'}.'@ebi.ac.uk',    # NB: your EBI address may differ from the Sanger one!

            # code directories:
        sec_root_dir   => '/software/ensembl/compara',
        blast_bin_dir  => $self->o('sec_root_dir') . '/ncbi-blast-2.2.22+/bin',
        mcl_bin_dir    => $self->o('sec_root_dir') . '/mcl-09-308/bin',
        mafft_root_dir => $self->o('sec_root_dir') . '/mafft-6.522',
            
            # data directories:
        work_dir       => $ENV{'HOME'}.'/families_'.$self->o('release').$self->o('rel_suffix'),
        blastdb_dir    => '/lustre/scratch103/ensembl/'.$ENV{'USER'}.'/families_'.$self->o('release').$self->o('rel_suffix'),
        blastdb_name   => 'metazoa_'.$self->o('release').'.pep',
        tcx_name       => 'families_'.$self->o('release').'.tcx',
        itab_name      => 'families_'.$self->o('release').'.itab',
        mcl_name       => 'families_'.$self->o('release').'.mcl',

            # family database connection parameters (our main database):
        pipeline_db => {
            -host   => 'compara2',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => $ENV{'USER'}.'_compara_families_'.$self->o('release').$self->o('rel_suffix'),
        },

            # homology database connection parameters (we inherit half of the members and sequences from there):
        homology_db  => {
            -host   => 'compara3',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => 'avilella_compara_homology_'.$self->o('release'),
        },

        prev_rel_db => {     # used by the StableIdMapper as the reference
            -host   => 'compara1',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => 'lg4_ensembl_compara_57',
        },

        master_db => {     # used by the StableIdMapper as the location of the master 'mapping_session' table
            -host   => 'compara1',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => 'sf5_ensembl_compara_master',
        },
    };
}


sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # here we inherit creation of database, hive tables and compara tables
        
        'mysqldump '.$self->dbconn_2_mysql('homology_db', 0).' '.$self->o('homology_db','-dbname')
                    .' -t ncbi_taxa_name ncbi_taxa_node method_link genome_db species_set method_link_species_set '
                    .'| mysql '.$self->dbconn_2_mysql('pipeline_db', 1),

        'mysqldump '.$self->dbconn_2_mysql('homology_db', 0).' '.$self->o('homology_db','-dbname')
                   .' -t member sequence family family_member | sed "s/ENGINE=MyISAM/ENGINE=InnoDB/" '
                   .'| mysql '.$self->dbconn_2_mysql('pipeline_db', 1),

        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'ALTER TABLE member   AUTO_INCREMENT=100000001'",
        'mysql '.$self->dbconn_2_mysql('pipeline_db', 1)." -e 'ALTER TABLE sequence AUTO_INCREMENT=100000001'",

        'mkdir -p '.$self->o('work_dir'),
        'mkdir -p '.$self->o('blastdb_dir'),
    ];
}


sub pipeline_wide_parameters {  # these parameter values are visible to all analyses, can be overridden by parameters{} and input_id{}
    my ($self) = @_;
    return {
        'pipeline_name'     => 'fam'.$self->o('release').$self->o('rel_suffix'),    # name the pipeline to differentiate the submitted processes
        'email'             => $self->o('email'),                                   # for automatic notifications (may be unsupported by your Meadows)

        'work_dir'          => $self->o('work_dir'),                                # data directories and filenames
        'blastdb_dir'       => $self->o('blastdb_dir'),
        'blastdb_name'      => $self->o('blastdb_name'),

        'blast_bin_dir'     => $self->o('blast_bin_dir'),                           # binary & script directories
        'mcl_bin_dir'       => $self->o('mcl_bin_dir'),
        'mafft_root_dir'    => $self->o('mafft_root_dir'),

        'idprefixed'        => 1,                                                   # other options to sync different analyses
    };
}

sub resource_classes {
    my ($self) = @_;
    return {
         0 => { -desc => 'default, 8h',      'LSF' => '' },
         1 => { -desc => 'urgent',           'LSF' => '-q yesterday' },
         2 => { -desc => 'long compara2',    'LSF' => '-q long -R"select[mycompara2<1000] rusage[mycompara2=10:duration=10:decay=1]"' },
         3 => { -desc => 'high memory',      'LSF' => '-C0 -M20000000 -q hugemem -R"select[mem>20000] rusage[mem=20000]"' },    # 15G enough to load 450mln, 25G enough to load 850mln
         4 => { -desc => 'huge mem 4proc',   'LSF' => '-C0 -M40000000 -n 4 -q hugemem -R"select[ncpus>=4 && mem>40000] rusage[mem=40000] span[hosts=1]"' },
         5 => { -desc => 'himem compara2',   'LSF' => '-C0 -M14000000 -R"select[mycompara2<500 && mem>14000] rusage[mycompara2=10:duration=10:decay=1:mem=14000]"' },
         6 => { -desc => 'compara2',         'LSF' => '-R"select[mycompara2<500] rusage[mycompara2=10:duration=10:decay=1]"' },
    };
}

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'load_uniprot_factory',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputlist'       => ['FUN','HUM','MAM','ROD','VRT','INV'],
                'numeric'         =>  0,
                'fan_branch_code' => 2,
            },
            -input_ids => [
                { 'input_id' => { 'srs' => 'SWISSPROT', 'tax_div' => '$RangeStart' } },
                { 'input_id' => { 'srs' => 'SPTREMBL',  'tax_div' => '$RangeStart' } },
            ],
            -flow_into => {
                2 => [ 'load_uniprot' ],
            },
            -rc_id => 1,
        },

        {   -logic_name    => 'load_uniprot',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::LoadUniProt',
            -parameters    => { },
            -hive_capacity => 20,
            -input_ids     => [
                # (jobs for this analysis will be flown_into from the JobFactory above)
            ],
            -rc_id => 0,
        },
        
        {   -logic_name => 'dump_member_proteins',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::DumpMemberSequencesIntoFasta',
            -parameters => {
                'source_names' => [ 'ENSEMBLPEP','Uniprot/SWISSPROT','Uniprot/SPTREMBL' ],
            },
            -input_ids => [
                { 'fasta_name' => $self->o('work_dir').'/'.$self->o('blastdb_name'), },
            ],
            -wait_for  => [ 'load_uniprot_factory', 'load_uniprot' ],
            -rc_id => 1,
        },

        {   -logic_name => 'make_blastdb',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { },
            -input_ids => [
                { 'cmd' => "#blast_bin_dir#/makeblastdb -dbtype prot -parse_seqids -logfile #work_dir#/makeblastdb.log -in #work_dir#/#blastdb_name#", },
            ],
            -wait_for => [ 'dump_member_proteins' ],
            -rc_id => 1,
        },

        {   -logic_name => 'copy_blastdb_over',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { },
            -input_ids => [
                { 'cmd' => "cp #work_dir#/#blastdb_name#* #blastdb_dir#", },
            ],
            -wait_for => [ 'make_blastdb' ],
            -rc_id => 1,
        },

        {   -logic_name => 'family_blast_factory',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'inputquery'      => 'SELECT DISTINCT s.sequence_id FROM member m, sequence s WHERE m.sequence_id=s.sequence_id AND m.source_name IN ("Uniprot/SPTREMBL", "Uniprot/SWISSPROT", "ENSEMBLPEP") ',
                'step'            => 100,
                'numeric'         => 1,
                'fan_branch_code' => 2,
            },
            -input_ids => [
                { 'input_id' => { 'sequence_id' => '$RangeStart', 'minibatch' => '$RangeCount' }, },
            ],
            -wait_for => [ 'copy_blastdb_over' ],
            -flow_into => {
                2 => [ 'family_blast' ],
            },
            -rc_id => 1,
        },

        {   -logic_name    => 'family_blast',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::FamilyBlast',
            -parameters    => { },
            -hive_capacity => 1000,
            -input_ids     => [
                # (jobs for this analysis will be created by the JobFactory above)
            ],
            -rc_id => 2,
        },

        {   -logic_name => 'mcxload_matrix',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => {
                'db_conn'  => $self->dbconn_2_mysql('pipeline_db', 1), # also to conserve the valuable input_id space
            },
            -input_ids  => [
                { 'cmd' => "mysql #db_conn# -N -q -e 'select * from mcl_sparse_matrix' | #mcl_bin_dir#/mcxload -abc - -ri max -o #work_dir#/".$self->o('tcx_name')." -write-tab #work_dir#/".$self->o('itab_name'), },
            ],
            -wait_for => [ 'family_blast_factory', 'family_blast' ],
            -rc_id => 3,
        },

        {   -logic_name => 'mcl',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { },
            -input_ids => [
                { 'cmd' => "#mcl_bin_dir#/mcl #work_dir#/".$self->o('tcx_name')." -I 2.1 -t 4 -tf 'gq(50)' -scheme 6 -use-tab #work_dir#/".$self->o('itab_name')." -o #work_dir#/".$self->o('mcl_name'), },
            ],
            -wait_for => [ 'mcxload_matrix' ],
            -rc_id => 4,
        },

        {   -logic_name => 'parse_mcl',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::FamilyParseMCL',
            -parameters => { },
            -input_ids => [
                { 'mcl_name' => $self->o('work_dir').'/'.$self->o('mcl_name'), 'family_prefix' => 'fam'.$self->o('release').$self->o('rel_suffix'), },
            ],
            -wait_for => [ 'mcl' ],
            -rc_id => 1,
        },

# 1. Archiving sub-branch:
        {   -logic_name => 'archive_long_files',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters => { },
            -hive_capacity => 20, # to enable parallel branches
            -input_ids => [
                { 'cmd' => "gzip #work_dir#/".$self->o('tcx_name'), },
                { 'cmd' => "gzip #work_dir#/".$self->o('itab_name'), },
                { 'cmd' => "gzip #work_dir#/".$self->o('mcl_name'), },
            ],
            -wait_for => [ 'parse_mcl' ],
            -rc_id => 1,
        },
# (end of branch 1)

# 2. Mafft sub-branch:
        {   -logic_name => 'family_mafft_factory',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'randomize'  => 1,
                'numeric'    => 1,
                'input_id'   => { 'family_id' => '$RangeStart' },
            },
            -hive_capacity => 20, # to enable parallel branches
            -input_ids  => [
                { 'fan_branch_code' => 2, 'inputlist'  => [ 1, 2 ],},
                { 'fan_branch_code' => 3, 'inputquery' => 'SELECT family_id FROM family_member WHERE family_id>2 GROUP BY family_id HAVING count(*)>1',},
            ],
            -wait_for => [ 'parse_mcl' ],
            -flow_into => {
                2 => [ 'family_mafft_big'  ],
                3 => [ 'family_mafft_main' ],
            },
            -rc_id => 1,
        },

        {   -logic_name    => 'family_mafft_big',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::FamilyMafft',
            -parameters    => { },
            -hive_capacity => 20,
            -batch_size    => 1,
            -input_ids     => [
                # (jobs for this analysis will be created by the JobFactory above)
            ],
            -rc_id => 5,
        },

        {   -logic_name    => 'family_mafft_main',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::FamilyMafft',
            -parameters    => { },
            -hive_capacity => 400,
            -batch_size    =>  10,
            -input_ids     => [
                # (jobs for this analysis will be created by the JobFactory above)
            ],
            -rc_id => 6,
        },

        {   -logic_name => 'find_update_singleton_cigars',      # example of an SQL-session within a job (temporary table created, used and discarded)
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters => {
                'find_singletons' => "CREATE TEMPORARY TABLE singletons SELECT family_id, length(s.sequence) len, count(*) cnt FROM family_member fm, member m, sequence s WHERE fm.member_id=m.member_id AND m.sequence_id=s.sequence_id GROUP BY family_id HAVING cnt=1",
                'update_singleton_cigars' => "UPDATE family_member fm, member m, singletons st SET fm.cigar_line=concat(st.len, 'M') WHERE fm.family_id=st.family_id AND m.member_id=fm.member_id AND m.source_name<>'ENSEMBLGENE'",
            },
            -hive_capacity => 20, # to enable parallel branches
            -input_ids => [
                { 'sql' => [ "#find_singletons#", "#update_singleton_cigars#", ], },
            ],
            -wait_for => [ 'family_mafft_factory', 'family_mafft_big', 'family_mafft_main' ],
            -rc_id => 1,
        },

        {   -logic_name => 'insert_redundant_peptides',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters => { },
            -hive_capacity => 20, # to enable parallel branches
            -input_ids => [
                { 'sql' => "INSERT INTO family_member SELECT family_id, m2.member_id, cigar_line FROM family_member fm, member m1, member m2 WHERE fm.member_id=m1.member_id AND m1.sequence_id=m2.sequence_id AND m1.member_id<>m2.member_id", },
            ],
            -wait_for => [ 'find_update_singleton_cigars' ],
            -rc_id => 1,
        },

        {   -logic_name => 'insert_ensembl_genes',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters => { },
            -hive_capacity => 20, # to enable parallel branches
            -input_ids => [
                { 'sql' => "INSERT INTO family_member SELECT fm.family_id, m.gene_member_id, NULL FROM member m, family_member fm WHERE m.member_id=fm.member_id AND m.source_name='ENSEMBLPEP' GROUP BY family_id, gene_member_id", },
            ],
            -wait_for => [ 'insert_redundant_peptides' ],
            -rc_id => 1,
        },
# (end of branch 2)

# 3. Consensifier sub-branch:
        {   -logic_name => 'consensifier_factory',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'numeric'         => 1,
                'input_id'        => { 'family_id' => '$RangeStart', 'minibatch' => '$RangeCount'},
                'fan_branch_code' => 2,
            },
            -hive_capacity => 20, # run the two in parallel and enable parallel branches
            -input_ids  => [
                { 'step' => 1,   'inputquery' => 'SELECT family_id FROM family WHERE family_id<=200',},
                { 'step' => 100, 'inputquery' => 'SELECT family_id FROM family WHERE family_id>200',},
            ],
            -wait_for => [ 'parse_mcl' ],
            -flow_into => {
                2 => [ 'consensifier' ],
            },
            -rc_id => 1,
        },

        {   -logic_name    => 'consensifier',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::FamilyConsensifier',
            -parameters    => { },
            -hive_capacity => 400,
            -input_ids     => [
                # (jobs for this analysis will be created by the JobFactory above)
            ],
            -rc_id => 0,
        },
# (end of branch 3)

# job funnel:
        {   -logic_name    => 'family_idmap',
            -module        => 'Bio::EnsEMBL::Compara::RunnableDB::StableIdMapper',
            -parameters    => { 'master_db' => $self->o('master_db'), 'prev_rel_db' => $self->o('prev_rel_db') },
            -input_ids     => [
                { 'type' => 'f', 'release' => $self->o('release'), },
            ],
            -wait_for => [ 'archive_long_files', 'insert_ensembl_genes', 'consensifier_factory', 'consensifier' ],
            -rc_id => 1,
        },
        
        {   -logic_name => 'notify_pipeline_completed',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::NotifyByEmail',
            -parameters => { },
            -input_ids => [
                { 'subject' => "FamilyPipeline(".$self->o('release').") has completed", 'text' => "This is an automatic message.\nFamilyPipeline for release ".$self->o('release')." has completed.", },
            ],
            -wait_for => [ 'family_idmap' ],
            -rc_id => 1,
        },

        #
        ## Please remember that the stable_id_history will have to be MERGED in an intelligent way, and not just written over.
        #
    ];
}

1;
